# Napas RAG Quality MVP Runbook

> **STATUS (2026-05-16):** This Docker-based runbook is kept for historical reference. The active deployment path on this machine is Windows-native — see `docs/rag-quality-mvp/windows-native-stack.md` for the current `scripts/windows/*.ps1` workflow (install-middleware → setup-databases → configure-dify-env → start-stack → verify-wiring).
>
> The Configure RAGFlow Corpus, Configure Dify External Knowledge, and Configure Dify Chat App sections below remain accurate — they describe the RAGFlow and Dify UIs which behave the same whether the services run in Docker or natively.

## Purpose

Run a local proof with RAGFlow as the document engine and Dify as the chat/orchestration layer. The proof uses real, approved non-sensitive PDF/DOCX documents and evaluates answer quality, citations, and uncertainty handling.

## Official References Checked

- Dify Docker Compose deployment: https://docs.dify.ai/en/self-host/quick-start/docker-compose
- Dify External Knowledge connection: https://docs.dify.ai/en/use-dify/knowledge/connect-external-knowledge-base
- Dify External Knowledge API contract: https://docs.dify.ai/en/use-dify/knowledge/external-knowledge-api
- Dify environment variables: https://docs.dify.ai/en/self-host/configuration/environments
- RAGFlow quickstart: https://ragflow.org/index.html

## Local Ports

Use these local URLs for the MVP:

- RAGFlow UI: `http://localhost:8080`
- RAGFlow API base for Dify: `http://host.docker.internal:9380/api/v1/dify`
- Dify UI: `http://localhost:3000`
- Dify HTTPS host port: `3443`

Dify is mapped to host port `3000` because both RAGFlow and Dify default to host port `80`.

## Prerequisites

Run:

```powershell
docker --version
docker compose version
git --version
```

Expected:

- Docker is installed.
- Docker Compose is version `2.24.0` or newer for Dify.
- Git is installed.
- Docker Desktop is running.

On Windows, Docker Desktop with WSL 2 enabled is the supported Dify path. If Docker bind mounts are slow from a Windows path, clone the runtime repositories under a WSL Linux path and keep this repository for docs and evaluation files.

Corpus files, `.env`, API keys, provider credentials, and runtime clones must not be committed.

RAGFlow uses Elasticsearch by default. On Linux or WSL-backed Docker hosts, check the Elasticsearch host setting before starting RAGFlow:

```powershell
wsl -e sh -lc "sysctl vm.max_map_count"
```

Expected: value is at least `262144`. If it is lower, set it from the Linux host:

```bash
sudo sysctl -w vm.max_map_count=262144
```

The clone commands below are first-run commands. If `runtime\ragflow` or `runtime\dify` already exists, reuse it or delete it only after confirming no local data is needed.

## Start RAGFlow

From the repository root, run:

```powershell
git clone https://github.com/infiniflow/ragflow.git runtime\ragflow
Push-Location runtime\ragflow\docker
docker compose -f docker-compose.yml up -d
docker compose -f docker-compose.yml ps
Pop-Location
```

Check the RAGFlow server logs:

```powershell
docker logs ragflow-server --tail 120
```

Expected: logs show the RAGFlow server has started and listens on `0.0.0.0`.

Open:

```text
http://localhost
```

Create the local RAGFlow admin account if prompted.

This Windows host has TCP port `80` reserved, so this run uses `SVR_WEB_HTTP_PORT=8080` in `runtime/ragflow/docker/.env`. Docker Desktop is currently limited to about 7.6 GiB RAM, so this run also lowers RAGFlow Elasticsearch `MEM_LIMIT` to `2147483648` for the small MVP corpus.

Record the RAGFlow commit used in repo-root `eval/report.md`.

## Start Dify

From the repository root, run:

```powershell
$tag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/langgenius/dify/releases/latest').tag_name
git clone --branch $tag https://github.com/langgenius/dify.git runtime\dify
Push-Location runtime\dify\docker
Copy-Item -LiteralPath '.env.example' -Destination '.env'
```

Set Dify host ports so it does not conflict with RAGFlow:

```powershell
$envFile = '.env'
$content = Get-Content -LiteralPath $envFile
$content = $content -replace '^EXPOSE_NGINX_PORT=.*$', 'EXPOSE_NGINX_PORT=3000'
$content = $content -replace '^EXPOSE_NGINX_SSL_PORT=.*$', 'EXPOSE_NGINX_SSL_PORT=3443'
if (-not ($content -match '^EXPOSE_NGINX_PORT=')) { $content += 'EXPOSE_NGINX_PORT=3000' }
if (-not ($content -match '^EXPOSE_NGINX_SSL_PORT=')) { $content += 'EXPOSE_NGINX_SSL_PORT=3443' }
Set-Content -LiteralPath $envFile -Value $content -Encoding UTF8
```

Allow Dify's SSRF proxy to reach the local RAGFlow host endpoint:

```powershell
$squid = 'ssrf_proxy\squid.conf.template'
$content = Get-Content -LiteralPath $squid
$content = $content -replace '^(acl allowed_domains dstdomain .*)$', '$1 host.docker.internal'
Set-Content -LiteralPath $squid -Value $content -Encoding UTF8
```

Start Dify:

```powershell
docker compose -p dify up -d
docker compose -p dify ps
Pop-Location
```

Expected: Dify containers are `Up` or `healthy`.

Open:

```text
http://localhost:3000/install
```

Create the local Dify admin account. After setup, use:

```text
http://localhost:3000
```

Record the Dify release tag used in repo-root `eval/report.md`.

## Configure RAGFlow Corpus

In RAGFlow:

`eval/corpus-inventory.csv` and `eval/report.md` are repo-root paths. Create `eval/` before recording corpus and run notes.

1. Create one knowledge base or dataset named `napas-rag-quality-mvp`.
2. Upload 5-10 approved non-sensitive PDF/DOCX documents.
3. Start document parsing/indexing.
4. Record each document in `eval/corpus-inventory.csv`.
5. Record parsing failures in `eval/report.md`.
6. Generate or copy the API key needed by Dify.
7. Copy the RAGFlow knowledge base or dataset ID for Dify's External Knowledge ID field.

## Configure Dify External Knowledge

In Dify:

1. Configure one available LLM provider and model.
2. Go to Knowledge.
3. Open External Knowledge API.
4. Add an External Knowledge API:
   - Name: `RAGFlow Local`
   - API Endpoint: `http://host.docker.internal:9380/api/v1/dify`
   - API Key: use the RAGFlow API key from the local proof environment.
5. Create an external knowledge base:
   - Name: `napas-rag-quality-mvp`
   - External Knowledge API: `RAGFlow Local`
   - External Knowledge ID: use the RAGFlow knowledge base or dataset ID.
   - Top K: `5`
   - Score Threshold: enabled at `0.30`

Dify appends `/retrieval` to the External Knowledge API endpoint when it sends requests.

## Configure Dify Chat App

In Dify:

1. Create a Chat Assistant app named `Napas RAG Quality MVP`.
2. Attach the external knowledge base `napas-rag-quality-mvp`.
3. Paste the prompt from `docs/rag-quality-mvp/dify-grounded-answer-prompt.md`.
4. Save the app.
5. Ask one smoke-test question that is directly answered in the corpus.
6. Ask one smoke-test question that is not answered in the corpus.

Expected:

- The answered question includes evidence citations.
- The missing-evidence question receives an uncertainty response.

Record the smoke-test question, answer, citation result, and uncertainty result in repo-root `eval/report.md`.

## Shutdown

Stop Dify:

```powershell
Push-Location runtime\dify\docker
docker compose -p dify down
Pop-Location
```

Stop RAGFlow:

```powershell
Push-Location runtime\ragflow\docker
docker compose -f docker-compose.yml down
Pop-Location
```

Do not run `docker compose down -v` during the MVP unless the user explicitly asks to delete local service data.
