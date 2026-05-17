# Windows Native Stack Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Context: Architectural Role

This plan builds the **infrastructure foundation** for the Napas internal chatbot described in `agentic-rag-napas-plan.md`. Read that file first for the full 4-layer architecture and agentic patterns. The stack this plan manages maps to layers as follows:

| Service in `stack.local.json` | Architectural Layer | Role |
|---|---|---|
| `postgres` | Brain (Dify) | Dify app/user/conversation database |
| `qdrant` | Brain (Dify) | Vector store for Dify semantic search (replaces Weaviate) |
| `memurai-redis` | Brain + Memory | Shared cache / task queue for Dify and RAGFlow |
| `dify-api` | Brain (Dify) | Agent orchestration, ReAct loop, External KB client |
| `dify-web` | Brain (Dify) | Dify chat UI for the proof phase |
| `mysql` | Memory (RAGFlow) | RAGFlow metadata and document index database |
| `elasticsearch` | Memory (RAGFlow) | RAGFlow full-text + hybrid search index (8.11.3) |
| `minio` | Memory (RAGFlow) | RAGFlow document/object storage |
| `ragflow-api` | Memory (RAGFlow) | Document parsing, embedding, External KB API at :9380 |
| `ragflow-worker` | Memory (RAGFlow) | Async parsing and indexing task executor |
| `ragflow-web` | Memory (RAGFlow) | RAGFlow admin UI for corpus management |

The next plan after this one (`2026-05-16-wiring-ragflow-dify-agentic-rag.md`) covers connecting these layers and running the RAG quality evaluation.

---

**Goal:** Build PowerShell scripts that manage a local Windows-native multi-service stack without Docker Desktop.

**Architecture:** A JSON config declares services, ports, and runtime paths. Shared PowerShell helpers handle repo-relative path resolution, PID files, logs, status checks, and deletion safety. The command scripts call those helpers for bootstrap, start, stop, status, clean, and tests.

**Tech Stack:** Windows PowerShell, JSON config, `Start-Process`, PID files, TCP port checks.

---

### Task 1: Add Failing Smoke Test

**Files:**
- Create: `scripts/windows/test-stack-scripts.ps1`

- [x] **Step 1: Add a test script that expects stack scripts to exist**

The test creates a temporary config for `python -m http.server`, starts it through `start-stack.ps1`, verifies status JSON, stops it, and cleans the runtime folder.

- [x] **Step 2: Run the test before implementation**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\test-stack-scripts.ps1
```

Expected: failure because `start-stack.ps1` is not present yet.

### Task 2: Add Shared Stack Helpers

**Files:**
- Create: `scripts/windows/stack-common.ps1`

- [x] **Step 1: Implement shared helper functions**

Functions include repo-root detection, config loading, service selection, command resolution, PID/log path creation, TCP port checks, safe path checks, and runtime directory creation.

- [x] **Step 2: Run parser check**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command "$null = [scriptblock]::Create((Get-Content -Raw scripts\windows\stack-common.ps1))"
```

Expected: no parser errors.

### Task 3: Add Stack Command Scripts

**Files:**
- Create: `scripts/windows/bootstrap.ps1`
- Create: `scripts/windows/start-stack.ps1`
- Create: `scripts/windows/stop-stack.ps1`
- Create: `scripts/windows/status-stack.ps1`
- Create: `scripts/windows/clean-stack.ps1`
- Create: `scripts/windows/stack.example.json`

- [x] **Step 1: Implement bootstrap**

Create `runtime/windows-stack`, copy `stack.example.json` to `runtime/windows-stack/stack.local.json` if missing, and print prerequisite availability.

- [x] **Step 2: Implement start**

Start selected enabled services, write PID files, redirect logs, and wait for configured ports.

- [x] **Step 3: Implement stop**

Stop selected managed PIDs and remove stale PID files.

- [x] **Step 4: Implement status**

Print service process and port state, with `-AsJson` for tests.

- [x] **Step 5: Implement clean**

Remove PID files and selected logs/cache/data paths with repo-root safety checks.

### Task 4: Verify

**Files:**
- Read: `scripts/windows/*.ps1`
- Read: `scripts/windows/stack.example.json`

- [x] **Step 1: Run smoke test**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\test-stack-scripts.ps1
```

Expected: test starts and stops a local Python HTTP server successfully.

- [x] **Step 2: Run bootstrap**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\bootstrap.ps1
```

Expected: runtime folders exist and missing native dependencies are reported clearly.

### Follow-up: Native Middleware

- [x] Install or wire native Postgres and Qdrant (replaces Weaviate) for Dify — `scripts/windows/install-middleware.ps1 -PostgreSQL -Qdrant`.
- [x] Install or wire native MySQL, Elasticsearch 8.11.3, and MinIO for RAGFlow — `scripts/windows/install-middleware.ps1 -MySQL -Elasticsearch -MinIO`.
- [x] Provide `scripts/windows/setup-databases.ps1` to initialise PostgreSQL/MySQL data directories and create the `dify` and `rag_flow` databases.
- [x] Provide `scripts/windows/configure-dify-env.ps1` to write Qdrant/Postgres/Redis values into `runtime/dify/api/.env` idempotently with backup.
- [x] Provide `scripts/windows/verify-wiring.ps1` for application-layer connectivity checks (RAGFlow, Dify, Qdrant, Elasticsearch, MinIO, Redis, Postgres, MySQL).
- [x] Provide `scripts/windows/test-helper-scripts.ps1` to validate the helpers in dry-run/lifecycle modes.
- [ ] Run `scripts/windows/setup-databases.ps1 -All` after installing middleware.
- [ ] Run `scripts/windows/configure-dify-env.ps1 -DbPassword <pw> -RedisPassword <pw>` after cloning Dify into `runtime/dify`.
- [ ] Enable reviewed service entries in `runtime/windows-stack/stack.local.json` after their binaries and config files are ready.
- [ ] Run `scripts/windows/start-stack.ps1`, then `scripts/windows/verify-wiring.ps1` to confirm all layers respond.
