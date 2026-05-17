# Windows Native Stack Scripts Design

## Goal

Provide a Windows-native way to start, stop, inspect, and clean a local multi-service stack without Docker Desktop.

## Scope

This slice builds the orchestration layer only. It does not install Postgres, MySQL, Redis, Elasticsearch, MinIO, or project dependencies automatically. Bootstrap can prepare Corepack pnpm and install `uv` with explicit flags, while the scripts detect any remaining missing commands and fail with clear messages so the native services can be added incrementally.

## Architecture

The stack is configured by JSON. A shared PowerShell module loads the config, resolves paths relative to the repo root, manages PID files under `runtime/windows-stack/pids`, writes logs under `runtime/windows-stack/logs`, and performs basic TCP health checks.

The start script launches enabled services in dependency order using `Start-Process`. The stop script stops only services with managed PID files. The clean script removes logs, cache, PID files, and optionally data paths, with path safety checks to avoid deleting outside the repository.

## Commands

- `scripts/windows/bootstrap.ps1`: create runtime directories and local config from `stack.example.json`; optionally prepare Corepack pnpm and install `uv`.
- `scripts/windows/start-stack.ps1`: start configured services.
- `scripts/windows/stop-stack.ps1`: stop configured services using PID files.
- `scripts/windows/status-stack.ps1`: show process and port status.
- `scripts/windows/clean-stack.ps1`: clean managed runtime files.
- `scripts/windows/test-stack-scripts.ps1`: local smoke test using `python -m http.server`.

## Initial Service Config

The example config includes disabled placeholders for Dify and RAGFlow services because this machine currently lacks several native middleware binaries. Users can enable entries after installing dependencies and reviewing commands.

## Safety

The scripts never use Docker. Stop operations use recorded PID files. Clean operations resolve every deletion target and require it to stay inside the repository root. Data deletion requires an explicit `-Data -ConfirmDataLoss` combination.
