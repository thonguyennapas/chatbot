# Windows Native Stack Scripts

These scripts manage local Windows processes and Windows services without Docker Desktop.

## Bootstrap

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\bootstrap.ps1
```

This creates:

- `runtime/windows-stack/stack.local.json`
- `runtime/windows-stack/logs`
- `runtime/windows-stack/pids`
- `runtime/windows-stack/tmp`
- `runtime/windows-stack/data`

`runtime/windows-stack/stack.local.json` is the editable local config. It is ignored by git through the existing `runtime/` rule.

## Status

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\status-stack.ps1 -IncludeDisabled
```

Use this before enabling services. On this machine, `memurai-redis` is configured as a Windows service entry for Redis-compatible local service management.

## Start

Start all enabled services:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\start-stack.ps1
```

Start one service even if it is disabled in the config:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\start-stack.ps1 -Only memurai-redis
```

Windows services such as `memurai-redis` may require running PowerShell as Administrator, depending on local service control permissions.

Preview commands without starting:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\start-stack.ps1 -IncludeDisabled -DryRun
```

## Stop

Stop all enabled services:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\stop-stack.ps1
```

Stop one service:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\stop-stack.ps1 -Only memurai-redis
```

If service permissions are missing, `start-stack.ps1` and `stop-stack.ps1` report the Administrator/service-control requirement explicitly.

## Clean

Clear logs, cache, and stale PID files:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\clean-stack.ps1
```

Stop first, then clean:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\clean-stack.ps1 -StopFirst -IncludeDisabled
```

Delete data only when explicitly intended:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\clean-stack.ps1 -Data -ConfirmDataLoss
```

## Install Middleware

`install-middleware.ps1` downloads and installs all native middleware. Run it outside the sandbox (e.g. with `! ` prefix in Claude Code):

```powershell
# Install everything at once
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-middleware.ps1 -All

# Or per component
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-middleware.ps1 -PostgreSQL -MySQL -MinIO
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-middleware.ps1 -Elasticsearch
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-middleware.ps1 -Qdrant

# Preview without downloading
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\install-middleware.ps1 -All -DryRun
```

| Component | Method | Notes |
|---|---|---|
| PostgreSQL 17 | winget `PostgreSQL.PostgreSQL.17` | For Dify. Adds `postgres` to PATH. |
| MySQL 8.4 | winget `Oracle.MySQL` | For RAGFlow. Adds `mysqld` to PATH. |
| MinIO | winget `MinIO.Server` | For RAGFlow. Adds `minio` to PATH. |
| Elasticsearch 8.11.3 | zip download | winget only has 7.16.3; script downloads correct version to `runtime/windows-stack/bin/elasticsearch/`. |
| Qdrant | zip download | Replaces Weaviate (not on winget). Binary at `runtime/windows-stack/bin/qdrant/qdrant.exe`. |

After install, reopen your terminal so winget-installed tools appear on PATH, then run bootstrap to verify:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\bootstrap.ps1
```

### Post-install: PostgreSQL setup

```powershell
initdb -D runtime\windows-stack\data\postgres --encoding UTF8 --auth trust
# start postgres temporarily:
postgres -D runtime\windows-stack\data\postgres
# in another terminal:
createdb -U postgres dify
```

### Post-install: MySQL setup

```powershell
mysqld --initialize-insecure --datadir=runtime\windows-stack\data\mysql
# start mysqld temporarily:
mysqld --console --datadir=runtime\windows-stack\data\mysql
# in another terminal:
mysql -u root -e "CREATE DATABASE rag_flow CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

### Post-install: Dify vector store config

Weaviate is replaced by Qdrant. Update `runtime/dify/api/.env`:

```
VECTOR_STORE=qdrant
QDRANT_URL=http://127.0.0.1:6333
# Remove or comment out any WEAVIATE_* lines
```

### Post-install: Setup Databases

After `install-middleware.ps1`, initialise the PostgreSQL and MySQL data directories and create the dify and rag_flow databases:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\setup-databases.ps1 -All
```

Per-database flags: `-PostgreSQL` / `-MySQL`. Pass `-MyRootPassword <pw>` to set the MySQL root password during init.

### Post-install: Configure Dify .env

After cloning Dify into `runtime/dify`, point its `api/.env` at the local stack (Qdrant + Postgres + Redis) idempotently:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\configure-dify-env.ps1 `
  -DbPassword '<postgres-password>' -RedisPassword '<redis-password>'
```

What the script does:
- Updates only specific keys (VECTOR_STORE, QDRANT_URL, DB_*, REDIS_*, CELERY_BROKER_URL) — other keys are preserved.
- Comments out any existing `WEAVIATE_*` keys (replaces them with Qdrant).
- Creates a timestamped `.env.bak.YYYYMMDDHHMMSS` backup before overwriting (skip with `-NoBackup`).
- Supports `-DryRun` and `-ShowDiff` for preview.

If `runtime/dify/api/.env` does not exist yet, the script seeds it from `runtime/dify/api/.env.example` first.

### Enable services

Edit `runtime/windows-stack/stack.local.json` and set `"enabled": true` for each service, then:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\start-stack.ps1
```

### Verify wiring

After services are up, check application-layer connectivity between Memory and Brain:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\verify-wiring.ps1
```

What it checks (each with timing and a remediation hint when it fails):
- RAGFlow API root and External KB endpoint (`/api/v1/dify/retrieval`).
- Dify API health.
- Qdrant collections list.
- Elasticsearch cluster info.
- MinIO live health.
- Redis PING (real Redis protocol handshake, not just TCP).
- PostgreSQL `dify` database (via `psql -tAc 'SELECT 1'`).
- MySQL `rag_flow` database (via `mysql -e 'SELECT 1'`).

Add `-AsJson` for programmatic consumption. Add `-RagflowApiKey` and `-RagflowDataset` for end-to-end External KB validation.

### Run test suite

Validate all helper scripts work correctly in dry-run / lifecycle modes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\test-helper-scripts.ps1
```

This exercises install-middleware (dry-run), setup-databases (dry-run), configure-dify-env (full lifecycle against a temp `.env`), and verify-wiring (JSON shape).

## Native Middleware Notes

- Elasticsearch 8.11.3 and Qdrant are downloaded as local binaries to `runtime/windows-stack/bin/` (gitignored via `runtime/` rule). They are referenced by relative path in `stack.local.json`, not via PATH.
- The existing `Memurai` Windows service covers Redis. Start/stop requires Administrator or service-control permissions. Dify and RAGFlow use different default Redis passwords — align config before sharing one instance.
- Dify compose defaults used PostgreSQL 15; the stack here targets 17. If Dify's `api/.env` has `DB_VERSION` set, update it accordingly.
