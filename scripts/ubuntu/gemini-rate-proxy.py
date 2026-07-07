#!/usr/bin/env python3
"""
Rate-limiting reverse proxy for Google Gemini API.

Sits between Dify and generativelanguage.googleapis.com,
enforcing a token-bucket rate limit (default: 150 RPM) to avoid
the 200 RPM/region hard cap on Google's side.

Usage:
    pip install fastapi uvicorn httpx
    python gemini-rate-proxy.py              # default: 150 RPM on port 8089
    RPM_LIMIT=100 python gemini-rate-proxy.py  # custom RPM

Configure Dify:
    In Dify .env or the Gemini model-provider plugin settings,
    route traffic through this proxy by setting the environment variable:
        SSRF_PROXY_ALL_URL=http://127.0.0.1:8089
    OR configure iptables/hosts-level redirect.

    Alternatively, use Dify's "OpenAI-API-compatible" provider
    pointing to http://127.0.0.1:8089/v1beta (see README).
"""

import asyncio
import logging
import os
import time
from threading import Lock

import httpx
import uvicorn
from fastapi import FastAPI, Request, Response

# ── Config ──────────────────────────────────────────────────────
RPM_LIMIT = int(os.environ.get("RPM_LIMIT", "150"))          # requests / minute
UPSTREAM   = "https://generativelanguage.googleapis.com"
PORT       = int(os.environ.get("PROXY_PORT", "8089"))
TIMEOUT    = 120  # seconds — embedding can be slow for large batches

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [proxy] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("gemini-proxy")

# ── Token bucket ────────────────────────────────────────────────
class TokenBucket:
    """Thread-safe token-bucket rate limiter."""

    def __init__(self, rpm: int):
        self.capacity = rpm
        self.tokens = float(rpm)
        self.refill_rate = rpm / 60.0        # tokens per second
        self.last_refill = time.monotonic()
        self._lock = Lock()
        self._waiters = 0

    def _refill(self):
        now = time.monotonic()
        elapsed = now - self.last_refill
        self.tokens = min(self.capacity, self.tokens + elapsed * self.refill_rate)
        self.last_refill = now

    async def acquire(self):
        """Wait until a token is available, then consume it."""
        while True:
            with self._lock:
                self._refill()
                if self.tokens >= 1:
                    self.tokens -= 1
                    return
                # Calculate wait time for next token
                wait = (1.0 - self.tokens) / self.refill_rate
            self._waiters += 1
            log.info("Rate limit reached (%d waiters), sleeping %.1fs", self._waiters, wait)
            await asyncio.sleep(wait)
            self._waiters -= 1


bucket = TokenBucket(RPM_LIMIT)

# ── FastAPI app ─────────────────────────────────────────────────
app = FastAPI(title="Gemini Rate Proxy")


@app.api_route("/{path:path}", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
async def proxy(request: Request, path: str):
    # 1. Rate-limit
    await bucket.acquire()

    # 2. Build upstream URL (preserve query params like ?key=...)
    upstream_url = f"{UPSTREAM}/{path}"
    if request.query_params:
        upstream_url += "?" + str(request.query_params)

    # 3. Forward headers (drop hop-by-hop)
    headers = {
        k: v for k, v in request.headers.items()
        if k.lower() not in ("host", "transfer-encoding", "connection")
    }
    headers["host"] = "generativelanguage.googleapis.com"

    body = await request.body()

    log.info(
        "%s /%s  (tokens=%.0f, waiters=%d)",
        request.method, path, bucket.tokens, bucket._waiters,
    )

    # 4. Forward to Google
    async with httpx.AsyncClient(timeout=TIMEOUT) as client:
        resp = await client.request(
            method=request.method,
            url=upstream_url,
            headers=headers,
            content=body,
        )

    # 5. Return response
    excluded = {"transfer-encoding", "content-encoding", "content-length"}
    resp_headers = {
        k: v for k, v in resp.headers.items()
        if k.lower() not in excluded
    }

    return Response(
        content=resp.content,
        status_code=resp.status_code,
        headers=resp_headers,
    )


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "rpm_limit": RPM_LIMIT,
        "tokens_available": round(bucket.tokens, 1),
    }


# ── Main ────────────────────────────────────────────────────────
if __name__ == "__main__":
    log.info("Starting Gemini rate-limit proxy: %d RPM, port %d", RPM_LIMIT, PORT)
    log.info("Upstream: %s", UPSTREAM)
    uvicorn.run(app, host="0.0.0.0", port=PORT, log_level="warning")
