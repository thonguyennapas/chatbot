# Napas RAG Quality MVP Implementation Plan

> **STATUS (2026-05-16):** This Docker-based plan has been superseded for the Windows-native deployment path due to Docker Desktop API instability and vmmemWSL load on the target machine. The runtime infrastructure now uses:
>
> - Infrastructure setup: `docs/superpowers/plans/2026-05-16-windows-native-stack-scripts.md`
> - Wiring + evaluation: `docs/superpowers/plans/2026-05-16-wiring-ragflow-dify-agentic-rag.md`
>
> The Files Created tasks (Tasks 1-6 below) are still valid — they produced `.gitignore`, the runbook, the grounded-answer prompt, and the eval/*.csv templates that the Windows-native flow continues to use. Tasks 7-10 (Docker deployment, corpus ingestion, evaluation) are replaced by the Windows-native wiring plan above. Keep this file for historical context.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a local RAGFlow + Dify quality proof that answers from real non-sensitive PDF/DOCX documents with citations and uncertainty handling.

**Architecture:** RAGFlow runs locally in Docker as the document engine. Dify runs locally in Docker as the chat and orchestration layer, with Dify connected to RAGFlow through the External Knowledge API. This repository stores the runbook, prompt, corpus inventory, evaluation questions, and evaluation report; corpus files and secrets stay outside git.

**Tech Stack:** Docker Desktop, Docker Compose, RAGFlow, Dify, PowerShell, CSV, Markdown.

---

## Scope Check

This plan implements one subsystem: the Thin Vertical RAG Proof from the approved design spec. It does not build the custom Next.js website, SSO/RBAC, admin panel, event workflows, API gateway, OpenRouter routing, or local confidential-data model routing.

## File Structure

- Create: `.gitignore`
  - Keeps secrets, local runtime clones, corpus files, and logs out of version control.
- Create: `docs/rag-quality-mvp/runbook.md`
  - Operator-facing setup and configuration steps for local RAGFlow + Dify.
- Create: `docs/rag-quality-mvp/dify-grounded-answer-prompt.md`
  - Prompt text to paste into the Dify chat app.
- Create: `eval/corpus-inventory.csv`
  - Inventory of approved non-sensitive PDF/DOCX files used in the proof.
- Create: `eval/questions.csv`
  - Evaluation question set with expected evidence and answerability.
- Create: `eval/report.md`
  - Manual evaluation report and next-slice recommendation.
- Runtime only, not committed: `runtime/ragflow`
  - Local clone of the RAGFlow repository.
- Runtime only, not committed: `runtime/dify`
  - Local clone of the Dify repository.
- Runtime only, not committed: `corpus/`
  - Local storage for approved test documents when the owner permits local copies.

## Commit Discipline

This workspace was not a git repository when this plan was written. At each commit step:

1. Run `git rev-parse --is-inside-work-tree`.
2. If it prints `true`, run the listed `git add` and `git commit` commands.
3. If it fails, do not run `git init`; record the changed files in the execution summary instead.

## Task 1: Create Repository Safety Files

**Files:**
- Create: `.gitignore`
- Create directory: `docs/rag-quality-mvp`
- Create directory: `eval`
- Create directory: `runtime`
- Create directory: `corpus`

- [ ] **Step 1: Create directories**

Run:

```powershell
New-Item -ItemType Directory -Force -Path 'docs\rag-quality-mvp','eval','runtime','corpus'
```

Expected: PowerShell returns directory objects or no error.

- [ ] **Step 2: Add `.gitignore`**

Apply this patch:

```patch
*** Begin Patch
*** Add File: .gitignore
+# Local secrets
+.env
+.env.*
+*.pem
+*.key
+
+# Local runtime clones and generated service data
+runtime/
+
+# Local document corpus for the proof
+corpus/
+
+# Logs and evaluation scratch output
+*.log
+logs/
+tmp/
+
+# OS/editor noise
+.DS_Store
+Thumbs.db
+.vscode/
+.idea/
*** End Patch
```

- [ ] **Step 3: Verify ignored paths**

Run:

```powershell
Get-Content -LiteralPath '.gitignore'
```

Expected: output includes `runtime/`, `corpus/`, `.env`, and `*.log`.

- [ ] **Step 4: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add .gitignore
git commit -m "chore: add local rag mvp ignore rules"
```

If the command fails because this is not a git repository, continue without committing.

## Task 2: Create The Local Deployment Runbook

**Files:**
- Create: `docs/rag-quality-mvp/runbook.md`

- [ ] **Step 1: Add the runbook**

Apply this patch:

```patch
*** Begin Patch
*** Add File: docs/rag-quality-mvp/runbook.md
+# Napas RAG Quality MVP Runbook
+
+## Purpose
+
+Run a local proof with RAGFlow as the document engine and Dify as the chat/orchestration layer. The proof uses real, approved non-sensitive PDF/DOCX documents and evaluates answer quality, citations, and uncertainty handling.
+
+## Official References Checked
+
+- Dify Docker Compose deployment: https://docs.dify.ai/en/self-host/quick-start/docker-compose
+- Dify External Knowledge connection: https://docs.dify.ai/en/use-dify/knowledge/connect-external-knowledge-base
+- Dify External Knowledge API contract: https://docs.dify.ai/en/use-dify/knowledge/external-knowledge-api
+- Dify environment variables: https://docs.dify.ai/en/self-host/configuration/environments
+- RAGFlow quickstart: https://ragflow.org/index.html
+
+## Local Ports
+
+Use these local URLs for the MVP:
+
+- RAGFlow UI: `http://localhost`
+- RAGFlow API base for Dify: `http://host.docker.internal:9380/api/v1/dify`
+- Dify UI: `http://localhost:3000`
+- Dify HTTPS host port: `3443`
+
+Dify is mapped to host port `3000` because both RAGFlow and Dify default to host port `80`.
+
+## Prerequisites
+
+Run:
+
+```powershell
+docker --version
+docker compose version
+git --version
+```
+
+Expected:
+
+- Docker is installed.
+- Docker Compose is version `2.24.0` or newer for Dify.
+- Git is installed.
+- Docker Desktop is running.
+
+On Windows, Docker Desktop with WSL 2 enabled is the supported Dify path. If Docker bind mounts are slow from a Windows path, clone the runtime repositories under a WSL Linux path and keep this repository for docs and evaluation files.
+
+RAGFlow uses Elasticsearch by default. On Linux or WSL-backed Docker hosts, check the Elasticsearch host setting before starting RAGFlow:
+
+```powershell
+wsl -e sh -lc "sysctl vm.max_map_count"
+```
+
+Expected: value is at least `262144`. If it is lower, set it from the Linux host:
+
+```bash
+sudo sysctl -w vm.max_map_count=262144
+```
+
+## Start RAGFlow
+
+From the repository root, run:
+
+```powershell
+git clone https://github.com/infiniflow/ragflow.git runtime\ragflow
+Push-Location runtime\ragflow\docker
+docker compose -f docker-compose.yml up -d
+docker compose -f docker-compose.yml ps
+Pop-Location
+```
+
+Check the RAGFlow server logs:
+
+```powershell
+docker logs ragflow-server --tail 120
+```
+
+Expected: logs show the RAGFlow server has started and listens on `0.0.0.0`.
+
+Open:
+
+```text
+http://localhost
+```
+
+Create the local RAGFlow admin account if prompted.
+
+## Start Dify
+
+From the repository root, run:
+
+```powershell
+$tag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/langgenius/dify/releases/latest').tag_name
+git clone --branch $tag https://github.com/langgenius/dify.git runtime\dify
+Push-Location runtime\dify\docker
+Copy-Item -LiteralPath '.env.example' -Destination '.env'
+```
+
+Set Dify host ports so it does not conflict with RAGFlow:
+
+```powershell
+$envFile = '.env'
+$content = Get-Content -LiteralPath $envFile
+$content = $content -replace '^EXPOSE_NGINX_PORT=.*$', 'EXPOSE_NGINX_PORT=3000'
+$content = $content -replace '^EXPOSE_NGINX_SSL_PORT=.*$', 'EXPOSE_NGINX_SSL_PORT=3443'
+if (-not ($content -match '^EXPOSE_NGINX_PORT=')) { $content += 'EXPOSE_NGINX_PORT=3000' }
+if (-not ($content -match '^EXPOSE_NGINX_SSL_PORT=')) { $content += 'EXPOSE_NGINX_SSL_PORT=3443' }
+Set-Content -LiteralPath $envFile -Value $content
+```
+
+Allow Dify's SSRF proxy to reach the local RAGFlow host endpoint:
+
+```powershell
+$squid = 'ssrf_proxy\squid.conf.template'
+$content = Get-Content -LiteralPath $squid
+$content = $content -replace '^(acl allowed_domains dstdomain .*)$', '$1 host.docker.internal localhost'
+Set-Content -LiteralPath $squid -Value $content
+```
+
+Start Dify:
+
+```powershell
+docker compose up -d
+docker compose ps
+Pop-Location
+```
+
+Expected: Dify containers are `Up` or `healthy`.
+
+Open:
+
+```text
+http://localhost:3000/install
+```
+
+Create the local Dify admin account. After setup, use:
+
+```text
+http://localhost:3000
+```
+
+## Configure RAGFlow Corpus
+
+In RAGFlow:
+
+1. Create one knowledge base or dataset named `napas-rag-quality-mvp`.
+2. Upload 5-10 approved non-sensitive PDF/DOCX documents.
+3. Start document parsing/indexing.
+4. Record each document in `eval/corpus-inventory.csv`.
+5. Record parsing failures in `eval/report.md`.
+6. Generate or copy the API key needed by Dify.
+7. Copy the RAGFlow knowledge base or dataset ID for Dify's External Knowledge ID field.
+
+## Configure Dify External Knowledge
+
+In Dify:
+
+1. Configure one available LLM provider and model.
+2. Go to Knowledge.
+3. Open External Knowledge API.
+4. Add an External Knowledge API:
+   - Name: `RAGFlow Local`
+   - API Endpoint: `http://host.docker.internal:9380/api/v1/dify`
+   - API Key: use the RAGFlow API key from the local proof environment.
+5. Create an external knowledge base:
+   - Name: `napas-rag-quality-mvp`
+   - External Knowledge API: `RAGFlow Local`
+   - External Knowledge ID: use the RAGFlow knowledge base or dataset ID.
+   - Top K: `5`
+   - Score Threshold: enabled at `0.30`
+
+Dify appends `/retrieval` to the External Knowledge API endpoint when it sends requests.
+
+## Configure Dify Chat App
+
+In Dify:
+
+1. Create a Chat Assistant app named `Napas RAG Quality MVP`.
+2. Attach the external knowledge base `napas-rag-quality-mvp`.
+3. Paste the prompt from `docs/rag-quality-mvp/dify-grounded-answer-prompt.md`.
+4. Save the app.
+5. Ask one smoke-test question that is directly answered in the corpus.
+6. Ask one smoke-test question that is not answered in the corpus.
+
+Expected:
+
+- The answered question includes evidence citations.
+- The missing-evidence question receives an uncertainty response.
+
+## Shutdown
+
+Stop Dify:
+
+```powershell
+Push-Location runtime\dify\docker
+docker compose down
+Pop-Location
+```
+
+Stop RAGFlow:
+
+```powershell
+Push-Location runtime\ragflow\docker
+docker compose -f docker-compose.yml down
+Pop-Location
+```
+
+Do not run `docker compose down -v` during the MVP unless the user explicitly asks to delete local service data.
*** End Patch
```

- [ ] **Step 2: Verify runbook source links and required ports**

Run:

```powershell
Select-String -Path 'docs\rag-quality-mvp\runbook.md' -Pattern 'http://localhost:3000','http://host.docker.internal:9380/api/v1/dify','EXPOSE_NGINX_PORT=3000'
```

Expected: all three patterns are found.

- [ ] **Step 3: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add docs/rag-quality-mvp/runbook.md
git commit -m "docs: add rag quality mvp runbook"
```

If the command fails because this is not a git repository, continue without committing.

## Task 3: Create The Dify Grounded Answer Prompt

**Files:**
- Create: `docs/rag-quality-mvp/dify-grounded-answer-prompt.md`

- [ ] **Step 1: Add the prompt file**

Apply this patch:

```patch
*** Begin Patch
*** Add File: docs/rag-quality-mvp/dify-grounded-answer-prompt.md
+# Dify Prompt: Napas RAG Quality MVP
+
+Paste the following prompt into the Dify chat app system/instruction field.
+
+```text
+You are a Napas internal knowledge assistant running in a RAG quality MVP.
+
+Your job is to answer only from the retrieved document evidence provided by the knowledge base.
+
+Rules:
+1. Use only retrieved evidence. Do not use outside knowledge.
+2. Cite the source document and page or section for every factual claim when source metadata is available.
+3. If page metadata is missing, cite the document title and the most specific section, heading, or chunk identifier available.
+4. If the retrieved evidence is insufficient, say: "The provided documents do not contain enough information to answer this."
+5. Do not invent policy, deadlines, thresholds, names, owners, approvals, fees, process steps, or exceptions.
+6. If retrieved documents conflict, state that the documents conflict and cite both sources.
+7. Keep the answer concise and operational.
+8. Separate evidence from interpretation when the answer requires a conclusion.
+
+Answer format:
+
+Answer:
+<direct answer in 1-5 short paragraphs>
+
+Citations:
+- <document title>, <page/section/chunk metadata>
+
+Evidence notes:
+- <brief note explaining which retrieved evidence supports the answer>
+
+If the answer is not supported, use this format:
+
+Answer:
+The provided documents do not contain enough information to answer this.
+
+Citations:
+- None
+
+Evidence notes:
+- The retrieved evidence did not contain the requested fact or process step.
+```
*** End Patch
```

- [ ] **Step 2: Verify required uncertainty phrase**

Run:

```powershell
Select-String -Path 'docs\rag-quality-mvp\dify-grounded-answer-prompt.md' -Pattern 'The provided documents do not contain enough information to answer this.'
```

Expected: the exact uncertainty sentence appears at least twice.

- [ ] **Step 3: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add docs/rag-quality-mvp/dify-grounded-answer-prompt.md
git commit -m "docs: add grounded answer prompt"
```

If the command fails because this is not a git repository, continue without committing.

## Task 4: Create Corpus Inventory

**Files:**
- Create: `eval/corpus-inventory.csv`

- [ ] **Step 1: Add the corpus inventory CSV**

Apply this patch:

```patch
*** Begin Patch
*** Add File: eval/corpus-inventory.csv
+doc_id,file_name,document_type,business_topic,page_count,owner_or_source,approved_non_sensitive,stored_in_repo,known_parsing_concerns,ragflow_dataset_name,ingestion_status,notes
*** End Patch
```

- [ ] **Step 2: Verify CSV headers**

Run:

```powershell
$headers = (Get-Content -LiteralPath 'eval\corpus-inventory.csv' -TotalCount 1).Split(',')
$headers
```

Expected: output includes `doc_id`, `file_name`, `approved_non_sensitive`, `ragflow_dataset_name`, and `ingestion_status`.

- [ ] **Step 3: Populate corpus inventory after documents are selected**

For each approved PDF/DOCX file, add one row with these values:

```csv
DOC-001,example-policy.pdf,pdf,payments process,12,operations,true,false,no known issues,napas-rag-quality-mvp,indexed,approved for local RAG proof
```

Use sequential IDs from `DOC-001` through the final document. Replace `example-policy.pdf`, `payments process`, `12`, and `operations` with the actual approved document values during execution. Set `stored_in_repo` to `false` unless the document owner explicitly permits repository storage.

- [ ] **Step 4: Validate corpus inventory row count**

Run:

```powershell
$rows = Import-Csv -LiteralPath 'eval\corpus-inventory.csv'
$rows.Count
$rows | Format-Table doc_id,file_name,approved_non_sensitive,ingestion_status
```

Expected after corpus selection: row count is between `5` and `10`, and every `approved_non_sensitive` value is `true`.

- [ ] **Step 5: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/corpus-inventory.csv
git commit -m "test: add rag corpus inventory"
```

If the command fails because this is not a git repository, continue without committing.

## Task 5: Create Evaluation Question Set

**Files:**
- Create: `eval/questions.csv`

- [ ] **Step 1: Add the evaluation CSV**

Apply this patch:

```patch
*** Begin Patch
*** Add File: eval/questions.csv
+question_id,question_type,question,expected_should_answer,expected_answer_notes,expected_sources,required_citation,pass_criteria
*** End Patch
```

- [ ] **Step 2: Add 15-25 corpus-specific questions**

After the corpus inventory has real rows, add questions using this exact row format:

```csv
Q001,factual,"What approval step is required before the process can continue?",true,"Answer should identify the approval step stated in the document.","DOC-001 page 4 or section 2.1",true,"Pass only if the answer names the approval step and cites DOC-001 page 4 or section 2.1."
Q002,missing-evidence,"What is the SLA for a process that is not described in these documents?",false,"Correct answer is that the provided documents do not contain enough information.","None",false,"Pass only if the answer refuses to invent an SLA."
Q003,citation,"Which document defines the exception handling rule?",true,"Answer should name the rule and cite the defining document.","DOC-002 section 3",true,"Pass only if the citation points to DOC-002 section 3."
```

Replace the sample question text and source references with facts from the selected documents. Keep at least:

- 3 rows with `question_type` set to `citation`.
- 3 rows with `question_type` set to `missing-evidence`.
- 2 rows with `question_type` set to `comparison` if the corpus naturally supports cross-document comparison.

- [ ] **Step 3: Validate question counts**

Run:

```powershell
$rows = Import-Csv -LiteralPath 'eval\questions.csv'
"total=$($rows.Count)"
$rows | Group-Object question_type | Select-Object Name,Count
"missing-evidence=$((($rows | Where-Object question_type -eq 'missing-evidence')).Count)"
"citation=$((($rows | Where-Object question_type -eq 'citation')).Count)"
```

Expected after questions are added:

- `total` is between `15` and `25`.
- `missing-evidence` is at least `3`.
- `citation` is at least `3`.

- [ ] **Step 4: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/questions.csv
git commit -m "test: add rag evaluation questions"
```

If the command fails because this is not a git repository, continue without committing.

## Task 6: Create Manual Evaluation Report Template

**Files:**
- Create: `eval/report.md`

- [ ] **Step 1: Add the report template**

Apply this patch:

```patch
*** Begin Patch
*** Add File: eval/report.md
+# Napas RAG Quality MVP Evaluation Report
+
+Date: 2026-05-14
+
+## Environment
+
+- RAGFlow URL: `http://localhost`
+- Dify URL: `http://localhost:3000`
+- Dify app name: `Napas RAG Quality MVP`
+- RAGFlow dataset name: `napas-rag-quality-mvp`
+- LLM provider/model used in Dify:
+- Evaluator:
+
+## Corpus Summary
+
+| Metric | Value |
+|---|---:|
+| Documents ingested | 0 |
+| PDF files | 0 |
+| DOCX files | 0 |
+| Documents with parsing issues | 0 |
+
+## Results Summary
+
+| Metric | Value |
+|---|---:|
+| Questions tested | 0 |
+| Pass | 0 |
+| Partial | 0 |
+| Fail | 0 |
+| Citation failures | 0 |
+| Unsupported-answer failures | 0 |
+| Missing-evidence failures | 0 |
+| Retrieval/chunking failures | 0 |
+
+## Scoring Rubric
+
+- Pass: answer is supported by retrieved evidence, cites the expected source, and does not add unsupported facts.
+- Partial: answer is mostly correct but citation detail is incomplete or wording is ambiguous.
+- Fail: answer is wrong, unsupported, missing required uncertainty, or cites the wrong source.
+
+## Question-Level Results
+
+| Question ID | Result | Expected source | Actual citation | Failure reason | Notes |
+|---|---|---|---|---|---|
+
+## Ingestion Issues
+
+| Document ID | Issue | Impact | Action |
+|---|---|---|---|
+
+## Bad Retrieval Examples
+
+| Question ID | Retrieved evidence problem | Impact | Action |
+|---|---|---|---|
+
+## Citation Failures
+
+| Question ID | Expected citation | Actual citation | Action |
+|---|---|---|---|
+
+## Unsupported Answer Failures
+
+| Question ID | Unsupported claim | Expected behavior | Action |
+|---|---|---|---|
+
+## Recommendation For Next Build Slice
+
+Choose one:
+
+- Improve ingestion if parsing or retrieval quality blocks trusted answers.
+- Add the custom website if the RAG quality loop is strong enough for a user-facing proof.
+- Add access control if safe internal rollout is the main blocker.
+
+Recommendation:
+
+Evidence:
*** End Patch
```

- [ ] **Step 2: Verify report sections**

Run:

```powershell
Select-String -Path 'eval\report.md' -Pattern 'Results Summary','Scoring Rubric','Recommendation For Next Build Slice'
```

Expected: all three section names are found.

- [ ] **Step 3: Commit if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/report.md
git commit -m "test: add rag evaluation report template"
```

If the command fails because this is not a git repository, continue without committing.

## Task 7: Start Local RAGFlow And Dify

**Files:**
- Runtime create: `runtime/ragflow`
- Runtime create: `runtime/dify`
- Modify runtime only: `runtime/dify/docker/.env`
- Modify runtime only: `runtime/dify/docker/ssrf_proxy/squid.conf.template`
- Read: `docs/rag-quality-mvp/runbook.md`

- [ ] **Step 1: Confirm prerequisites**

Run:

```powershell
docker --version
docker compose version
git --version
```

Expected: Docker, Docker Compose, and Git versions print without errors. Docker Compose must be `2.24.0` or newer.

- [ ] **Step 2: Check RAGFlow Elasticsearch host setting**

Run:

```powershell
wsl -e sh -lc "sysctl vm.max_map_count"
```

Expected: value is at least `262144`. If the value is lower, set it from the Linux host:

```bash
sudo sysctl -w vm.max_map_count=262144
```

- [ ] **Step 3: Clone and start RAGFlow**

Run:

```powershell
git clone https://github.com/infiniflow/ragflow.git runtime\ragflow
Push-Location runtime\ragflow\docker
docker compose -f docker-compose.yml up -d
docker compose -f docker-compose.yml ps
Pop-Location
```

Expected: RAGFlow containers start. If image download fails due to network restrictions, request permission to rerun the same command with network access.

- [ ] **Step 4: Check RAGFlow logs**

Run:

```powershell
docker logs ragflow-server --tail 120
```

Expected: logs show the RAGFlow server has started. If startup is still in progress, wait two minutes and rerun the command.

- [ ] **Step 5: Clone and configure Dify**

Run:

```powershell
$tag = (Invoke-RestMethod -Uri 'https://api.github.com/repos/langgenius/dify/releases/latest').tag_name
git clone --branch $tag https://github.com/langgenius/dify.git runtime\dify
Push-Location runtime\dify\docker
Copy-Item -LiteralPath '.env.example' -Destination '.env'
$envFile = '.env'
$content = Get-Content -LiteralPath $envFile
$content = $content -replace '^EXPOSE_NGINX_PORT=.*$', 'EXPOSE_NGINX_PORT=3000'
$content = $content -replace '^EXPOSE_NGINX_SSL_PORT=.*$', 'EXPOSE_NGINX_SSL_PORT=3443'
if (-not ($content -match '^EXPOSE_NGINX_PORT=')) { $content += 'EXPOSE_NGINX_PORT=3000' }
if (-not ($content -match '^EXPOSE_NGINX_SSL_PORT=')) { $content += 'EXPOSE_NGINX_SSL_PORT=3443' }
Set-Content -LiteralPath $envFile -Value $content
$squid = 'ssrf_proxy\squid.conf.template'
$content = Get-Content -LiteralPath $squid
$content = $content -replace '^(acl allowed_domains dstdomain .*)$', '$1 host.docker.internal localhost'
Set-Content -LiteralPath $squid -Value $content
```

Expected: `runtime\dify\docker\.env` exists, includes `EXPOSE_NGINX_PORT=3000`, and `ssrf_proxy\squid.conf.template` includes `host.docker.internal`.

- [ ] **Step 6: Start Dify**

Run:

```powershell
docker compose up -d
docker compose ps
Pop-Location
```

Expected: Dify containers are `Up` or `healthy`. If image download fails due to network restrictions, request permission to rerun the same command with network access.

- [ ] **Step 7: Verify host ports**

Run:

```powershell
docker ps --format "table {{.Names}}\t{{.Ports}}"
```

Expected:

- RAGFlow exposes host port `80`.
- Dify nginx exposes host port `3000`.

- [ ] **Step 8: Record runtime status in the report**

Edit `eval/report.md` and set:

```markdown
- RAGFlow URL: `http://localhost`
- Dify URL: `http://localhost:3000`
- Dify app name: `Napas RAG Quality MVP`
- RAGFlow dataset name: `napas-rag-quality-mvp`
```

- [ ] **Step 9: Commit report update if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/report.md
git commit -m "test: record local rag runtime status"
```

If the command fails because this is not a git repository, continue without committing.

## Task 8: Configure Corpus, External Knowledge, And Chat App

**Files:**
- Modify: `eval/corpus-inventory.csv`
- Read: `docs/rag-quality-mvp/dify-grounded-answer-prompt.md`
- Modify: `eval/report.md`

- [ ] **Step 1: Create RAGFlow dataset**

In the RAGFlow UI at `http://localhost`, create a dataset named:

```text
napas-rag-quality-mvp
```

Expected: the dataset exists and is visible in RAGFlow.

- [ ] **Step 2: Ingest approved documents**

Upload 5-10 approved non-sensitive PDF/DOCX documents to the RAGFlow dataset. For each document, add a row to `eval/corpus-inventory.csv` using this format:

```csv
DOC-001,example-policy.pdf,pdf,payments process,12,operations,true,false,no known issues,napas-rag-quality-mvp,indexed,approved for local RAG proof
```

Replace the sample values with actual approved document values. Keep `approved_non_sensitive` set to `true` only for documents the owner approved.

- [ ] **Step 3: Validate corpus inventory**

Run:

```powershell
$rows = Import-Csv -LiteralPath 'eval\corpus-inventory.csv'
"documents=$($rows.Count)"
$rows | Where-Object approved_non_sensitive -ne 'true' | Format-Table doc_id,file_name,approved_non_sensitive
```

Expected: document count is between `5` and `10`; the second command prints no rows.

- [ ] **Step 4: Create Dify External Knowledge API**

In Dify at `http://localhost:3000`:

```text
Knowledge -> External Knowledge API -> Add
Name: RAGFlow Local
API Endpoint: http://host.docker.internal:9380/api/v1/dify
API Key: use the local RAGFlow API key
```

Expected: Dify saves the External Knowledge API connection without a connection error.

- [ ] **Step 5: Create Dify external knowledge base**

In Dify:

```text
Knowledge -> Connect to an External Knowledge Base
External Knowledge Name: napas-rag-quality-mvp
External Knowledge API: RAGFlow Local
External Knowledge ID: use the RAGFlow dataset ID
Top K: 5
Score Threshold: enabled at 0.30
```

Expected: Dify creates the external knowledge base.

- [ ] **Step 6: Create Dify chat app**

In Dify:

```text
App type: Chat Assistant
Name: Napas RAG Quality MVP
Knowledge: napas-rag-quality-mvp
Prompt: paste the full prompt from docs/rag-quality-mvp/dify-grounded-answer-prompt.md
```

Expected: the app saves and can be opened in Dify's preview chat.

- [ ] **Step 7: Run two smoke tests**

Ask:

```text
Question 1: Use a direct factual question whose answer appears in DOC-001.
Question 2: What is the production database password?
```

Expected:

- Question 1 returns a grounded answer with a citation.
- Question 2 returns the uncertainty sentence and does not invent a password.

- [ ] **Step 8: Record smoke-test outcome**

In `eval/report.md`, add two rows under `Question-Level Results`:

```markdown
| SMOKE-001 | Pass | DOC-001 | <actual citation> |  | Direct factual smoke test |
| SMOKE-002 | Pass | None | None |  | Missing-evidence smoke test |
```

Replace `<actual citation>` with the citation returned by Dify.

- [ ] **Step 9: Commit evaluation setup if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/corpus-inventory.csv eval/report.md
git commit -m "test: configure rag corpus and smoke results"
```

If the command fails because this is not a git repository, continue without committing.

## Task 9: Populate And Run The Evaluation Pack

**Files:**
- Modify: `eval/questions.csv`
- Modify: `eval/report.md`

- [ ] **Step 1: Add corpus-specific questions**

Open `eval/questions.csv` and add 15-25 rows based on the ingested documents. Use this format:

```csv
Q001,factual,"What approval step is required before the process can continue?",true,"Answer should identify the approval step stated in the document.","DOC-001 page 4 or section 2.1",true,"Pass only if the answer names the approval step and cites DOC-001 page 4 or section 2.1."
Q002,missing-evidence,"What is the SLA for a process that is not described in these documents?",false,"Correct answer is that the provided documents do not contain enough information.","None",false,"Pass only if the answer refuses to invent an SLA."
Q003,citation,"Which document defines the exception handling rule?",true,"Answer should name the rule and cite the defining document.","DOC-002 section 3",true,"Pass only if the citation points to DOC-002 section 3."
```

Replace the sample text with real questions tied to the selected corpus.

- [ ] **Step 2: Validate question set**

Run:

```powershell
$rows = Import-Csv -LiteralPath 'eval\questions.csv'
"total=$($rows.Count)"
$rows | Group-Object question_type | Select-Object Name,Count
if ($rows.Count -lt 15 -or $rows.Count -gt 25) { throw 'Question count must be between 15 and 25.' }
if ((($rows | Where-Object question_type -eq 'missing-evidence')).Count -lt 3) { throw 'Need at least 3 missing-evidence questions.' }
if ((($rows | Where-Object question_type -eq 'citation')).Count -lt 3) { throw 'Need at least 3 citation questions.' }
```

Expected: counts print and no exception is thrown.

- [ ] **Step 3: Run each question manually in Dify**

For each row in `eval/questions.csv`:

1. Ask the exact `question` in the Dify app preview.
2. Compare the answer against `expected_answer_notes`.
3. Compare citations against `expected_sources`.
4. Mark result as `Pass`, `Partial`, or `Fail` using the scoring rubric in `eval/report.md`.
5. Add one row to `Question-Level Results`.

Use this row format:

```markdown
| Q001 | Pass | DOC-001 page 4 | DOC-001 page 4 |  | Answer named the expected approval step |
```

- [ ] **Step 4: Record failure details**

For every `Partial` or `Fail`, add one row to the most relevant section in `eval/report.md`:

```markdown
| Q004 | Retrieved chunk omitted the section containing the exception | Wrong answer risk | Increase Top K to 8 and retest Q004 |
```

Use `Ingestion Issues`, `Bad Retrieval Examples`, `Citation Failures`, or `Unsupported Answer Failures` based on the observed failure.

- [ ] **Step 5: Update summary counts**

In `eval/report.md`, update:

```markdown
| Questions tested | 0 |
| Pass | 0 |
| Partial | 0 |
| Fail | 0 |
| Citation failures | 0 |
| Unsupported-answer failures | 0 |
| Missing-evidence failures | 0 |
| Retrieval/chunking failures | 0 |
```

Replace each `0` with the final count from the manual evaluation.

- [ ] **Step 6: Commit evaluation results if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/questions.csv eval/report.md
git commit -m "test: record rag evaluation results"
```

If the command fails because this is not a git repository, continue without committing.

## Task 10: Decide The Next Build Slice

**Files:**
- Modify: `eval/report.md`

- [ ] **Step 1: Apply decision rule**

Use the final evaluation results:

```text
If parsing or retrieval failures explain most failures, recommend "Improve ingestion".
If answers are mostly correct and cited, recommend "Add the custom website".
If quality is acceptable but document access is the main rollout concern, recommend "Add access control".
```

- [ ] **Step 2: Write the recommendation**

In `eval/report.md`, fill:

```markdown
Recommendation:
<one of: Improve ingestion, Add the custom website, Add access control>

Evidence:
- <metric or example supporting the recommendation>
- <metric or example supporting the recommendation>
- <metric or example supporting the recommendation>
```

Use actual evaluation metrics and question IDs from the report.

- [ ] **Step 3: Validate report has no empty summary values**

Run:

```powershell
Select-String -Path 'eval\report.md' -Pattern '\| Questions tested \| 0 \|','\| Documents ingested \| 0 \|','Recommendation:\s*$'
```

Expected after final report completion: no matches.

- [ ] **Step 4: Commit final report if inside a git repo**

Run:

```powershell
git rev-parse --is-inside-work-tree
```

If the output is `true`, run:

```powershell
git add eval/report.md
git commit -m "docs: recommend next rag build slice"
```

If the command fails because this is not a git repository, continue without committing.

## Verification Checklist

Run these commands at the end:

```powershell
Get-ChildItem -Recurse -File docs\rag-quality-mvp,eval | Select-Object FullName
Select-String -Path 'docs\rag-quality-mvp\runbook.md' -Pattern 'http://localhost:3000','host.docker.internal'
Select-String -Path 'docs\rag-quality-mvp\dify-grounded-answer-prompt.md' -Pattern 'Use only retrieved evidence','Citations:'
Import-Csv -LiteralPath 'eval\corpus-inventory.csv' | Measure-Object
Import-Csv -LiteralPath 'eval\questions.csv' | Measure-Object
```

Expected:

- Runbook, prompt, corpus inventory, questions, and report files exist.
- Runbook includes Dify local port and RAGFlow host endpoint.
- Prompt includes grounding and citation instructions.
- Corpus inventory has 5-10 rows after corpus setup.
- Questions file has 15-25 rows after evaluation setup.

## Sources Used

- Dify Docker Compose deployment: https://docs.dify.ai/en/self-host/quick-start/docker-compose
- Dify External Knowledge connection: https://docs.dify.ai/en/use-dify/knowledge/connect-external-knowledge-base
- Dify External Knowledge API contract: https://docs.dify.ai/en/use-dify/knowledge/external-knowledge-api
- Dify environment variables: https://docs.dify.ai/en/self-host/configuration/environments
- RAGFlow quickstart: https://ragflow.org/index.html
