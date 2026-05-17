# Wiring RAGFlow + Dify and Running Agentic RAG Evaluation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for marking progress.

## Status: BLOCKED — Infra prerequisites not yet met (as of 2026-05-16)

Resume this plan only after the infra plan `2026-05-16-windows-native-stack-scripts.md` finishes its follow-up checklist. Snapshot of what is missing:

- [ ] **Middleware not installed.** `psql`, `mysql`, `postgres`, `mysqld`, `minio` not on PATH. `runtime/windows-stack/bin/qdrant/qdrant.exe` and `runtime/windows-stack/bin/elasticsearch/` do not exist.
      → Run `scripts/windows/install-middleware.ps1 -All` outside the sandbox.
- [ ] **Databases not initialised.** PostgreSQL `dify` DB and MySQL `rag_flow` DB do not exist yet.
      → Run `scripts/windows/setup-databases.ps1 -All` after install.
- [ ] **Dify `.env` not configured for the local stack.** `runtime/dify/api/.env` not pointed at Qdrant/Postgres/Redis.
      → Run `scripts/windows/configure-dify-env.ps1 -DbPassword <pw> -RedisPassword <pw>`.
- [ ] **All services disabled.** Every entry in `runtime/windows-stack/stack.local.json` has `"enabled": false`.
      → Edit the config to enable reviewed services, then `scripts/windows/start-stack.ps1`.
- [ ] **`verify-wiring.ps1` still reports 0/9 passing.** Re-run after the above steps; expect 7+ passing before starting Task 1 below.

Unblock signal: `scripts/windows/status-stack.ps1 -AsJson` shows all 8 prerequisite services with `isRunning=true` and `isPortOpen=true` per the Prerequisites table below.

## Context: Where This Fits

Read `agentic-rag-napas-plan.md` before executing this plan. That file defines the full 4-layer architecture:

> **RAGFlow = Memory** → **Dify = Brain** → **Custom Website = Face**

This plan is the second slice. It assumes the Windows-native stack from `2026-05-16-windows-native-stack-scripts.md` is fully running. It wires the Memory and Brain layers together, ingests a real Napas-style corpus, and validates the riskiest architectural assumption: **can the RAGFlow + Dify pipeline answer trustworthy, cited, uncertainty-aware responses from real internal documents?**

Agentic patterns validated in this slice (from `agentic-rag-napas-plan.md`):
- **Pattern 1 — ReAct:** Agent reasons before acting; handles multi-hop questions that cross document boundaries.
- **Pattern 2 — Self-RAG / CRAG:** After retrieval, Dify evaluates whether evidence is sufficient; missing-evidence path triggers the uncertainty response.
- **Pattern 3 — Multi-hop Retrieval:** Complex questions decomposed into sub-queries; answers synthesized across multiple retrieved chunks.

Patterns NOT in scope for this slice: Tool Use + Action (Pattern 4), Event-Driven (Pattern 5), custom Next.js Face, SSO/RBAC, OpenRouter routing.

**Design spec:** `docs/superpowers/specs/2026-05-14-agentic-rag-napas-rag-quality-mvp-design.md`

**Tech Stack:** RAGFlow native (Windows), Dify native (Windows), PowerShell, CSV, Markdown.

---

## Prerequisites

Before starting any task, verify all required services are running:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\status-stack.ps1 -AsJson
```

Required green (isRunning=true, isPortOpen=true):

| Service | Port | Layer |
|---|---|---|
| memurai-redis | 6379 | Shared |
| postgres | 5432 | Dify |
| qdrant | 6333 | Dify |
| mysql | 3306 | RAGFlow |
| elasticsearch | 1200 | RAGFlow |
| minio | 9000 | RAGFlow |
| ragflow-api | 9380 | Memory |
| dify-api | 5001 | Brain |

If any service is not running, return to `2026-05-16-windows-native-stack-scripts.md` and complete the infra setup first.

---

## Task 1: Verify Layer Connectivity

**Goal:** Confirm the Memory layer (RAGFlow) and Brain layer (Dify) can each be reached before wiring them together.

- [ ] **Step 1: Run the wiring verification script**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\verify-wiring.ps1
```

Expected: all checks marked OK except possibly the database queries if no password is set. Any FAIL row prints a `hint:` line with a remediation. Fix all FAILs before continuing.

For JSON output suitable for piping into other tools:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\verify-wiring.ps1 -AsJson
```

- [ ] **Step 2: Open Dify UI and create admin account if needed**

Open `http://localhost:3000`. If the install wizard appears, complete it. Record the admin email in the project notes.

- [ ] **Step 3: Open RAGFlow UI and create admin account if needed**

Open `http://localhost:9380` (or the port configured in `ragflow-api`). If the register page appears, create the local admin account. Record the email.

- [ ] **Step 4: Re-run verify-wiring with the new credentials**

After getting the RAGFlow API key (Task 3 Step 1) and dataset ID (Task 4 Step 1), re-run with those for an end-to-end check:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\windows\verify-wiring.ps1 `
  -RagflowApiKey '<key>' -RagflowDataset '<dataset-id>'
```

Expected: `ragflow: external KB endpoint` passes with HTTP 200 instead of 401.

---

## Task 2: Configure Dify LLM Provider

**Goal:** Connect Dify to a working LLM before creating the chat app.

- [ ] **Step 1: Add LLM provider in Dify**

In Dify UI: **Settings → Model Providers → Add Provider**

Choose the provider whose API key is available. Recommended for this proof (per `agentic-rag-napas-plan.md` tech stack):

| Provider | Model | Notes |
|---|---|---|
| Anthropic | claude-sonnet-4-6 | Best for text-heavy Napas policy documents |
| OpenRouter | (route to Claude or Gemini) | Use if a single gateway key is preferred |

Save and verify the model shows a green check.

- [ ] **Step 2: Set the default model**

In Dify: **Settings → Model Providers → System Model Settings → LLM** — set to the chosen model.

Expected: model name appears in the default LLM field.

---

## Task 3: Wire RAGFlow as Dify External Knowledge Base

**Goal:** Connect the Memory layer to the Brain layer through the RAGFlow External Knowledge API.

- [ ] **Step 1: Generate a RAGFlow API key**

In RAGFlow UI: **top-right avatar → API Key → Create new key**

Copy and store the key. Add it to `runtime/windows-stack/.secrets.env` (gitignored):

```text
RAGFLOW_API_KEY=ragflow-xxxxxxxxxxxxxxxx
```

- [ ] **Step 2: Get the RAGFlow dataset ID**

In RAGFlow UI: **Knowledge → napas-rag-quality-mvp → Settings**

Copy the dataset ID (UUID format). Store it alongside the API key:

```text
RAGFLOW_DATASET_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

If the dataset does not exist yet, create it in Task 4 Step 1 first and return here.

- [ ] **Step 3: Add RAGFlow as External Knowledge API in Dify**

In Dify UI: **Knowledge → External Knowledge API → Add**

```
Name:         RAGFlow Local
API Endpoint: http://localhost:9380/api/v1/dify
API Key:      <RAGFLOW_API_KEY>
```

Expected: Dify saves without a connection error. If it fails, check that `ragflow-api` is running and port 9380 is open.

- [ ] **Step 4: Create the external knowledge base in Dify**

In Dify UI: **Knowledge → Connect to an External Knowledge Base**

```
Name:                 napas-rag-quality-mvp
External KB API:      RAGFlow Local
External KB ID:       <RAGFLOW_DATASET_ID>
Top K:                5
Score Threshold:      0.30  (enable the toggle)
```

Expected: knowledge base created and listed under Knowledge.

---

## Task 4: Ingest Corpus into RAGFlow

**Goal:** Populate the Memory layer with real, approved, non-sensitive Napas-style documents.

Document selection criteria (from design spec):
- 5–10 files total.
- PDF and DOCX only (first slice).
- Prefer policy, procedure, FAQ, or operational-process documents.
- Avoid confidential customer data, credentials, production logs, or PII.
- Each file must be explicitly approved as non-sensitive by its owner before local use.

- [ ] **Step 1: Create the RAGFlow dataset**

In RAGFlow UI: **Knowledge → Create Dataset**

```
Name:     napas-rag-quality-mvp
Parser:   general  (switch to naive/paper if layout accuracy is poor)
Chunk method: general
```

Expected: dataset exists and has status "empty".

- [ ] **Step 2: Upload approved documents**

Upload each approved PDF/DOCX file into the dataset. For each file:

1. Click Upload in the RAGFlow dataset.
2. Start parsing.
3. Wait for status to show "finished" (or note the error).
4. Check the preview pane for at least one correctly parsed chunk.

- [ ] **Step 3: Record each document in corpus-inventory.csv**

For each uploaded file add one row to `eval/corpus-inventory.csv`:

```csv
DOC-001,<file_name>,<pdf|docx>,<business_topic>,<page_count>,<owner>,true,false,<parsing_notes>,napas-rag-quality-mvp,<indexed|failed>,<any notes>
```

Fields:
- `approved_non_sensitive`: must be `true` for every row.
- `stored_in_repo`: `false` unless owner explicitly approves repo storage.
- `ingestion_status`: `indexed` if RAGFlow shows finished, `failed` if parsing error.

- [ ] **Step 4: Validate corpus inventory**

```powershell
$rows = Import-Csv -LiteralPath 'eval\corpus-inventory.csv'
"documents=$($rows.Count)"
$rows | Where-Object approved_non_sensitive -ne 'true' | Format-Table doc_id,file_name
$rows | Where-Object ingestion_status -eq 'failed' | Format-Table doc_id,file_name,notes
```

Expected: 5–10 documents, all `approved_non_sensitive=true`, zero or documented failures.

- [ ] **Step 5: Record any parsing failures in report**

For any document where RAGFlow parsing failed or produced clearly wrong chunks, add a row to `eval/report.md` under `## Ingestion Issues`:

```markdown
| DOC-003 | RAGFlow split table across chunks | Wrong evidence in table-heavy questions | Switch parser to naive layout |
```

---

## Task 5: Build the Dify Chat App

**Goal:** Create the Brain layer chat interface that will be used for the evaluation.

- [ ] **Step 1: Create a Chat Assistant app**

In Dify UI: **Studio → Create App → Chat Assistant**

```
App name:  Napas RAG Quality MVP
```

- [ ] **Step 2: Attach the knowledge base**

In the app editor: **Context → Add → napas-rag-quality-mvp (external)**

Confirm the knowledge base appears in the context panel.

- [ ] **Step 3: Paste the grounded-answer prompt**

Open `docs/rag-quality-mvp/dify-grounded-answer-prompt.md` and copy the prompt text block. Paste into the app's **Instruction** field.

- [ ] **Step 4: Run two smoke tests**

In the Dify app preview chat:

```
Smoke 1: Ask a direct factual question whose answer exists in DOC-001.
Smoke 2: What is the production database password?
```

Expected:
- Smoke 1 returns an answer with a citation (document name and page/section).
- Smoke 2 returns the uncertainty sentence: "The provided documents do not contain enough information to answer this."

If Smoke 2 returns an invented password, the prompt grounding is not working — re-check the prompt paste and try again.

- [ ] **Step 5: Record smoke results in report**

In `eval/report.md` under `## Question-Level Results`:

```markdown
| SMOKE-001 | Pass | DOC-001 | <actual citation from Dify> |  | Direct factual smoke test |
| SMOKE-002 | Pass | None | None |  | Missing-evidence smoke test |
```

---

## Task 6: Populate Evaluation Questions

**Goal:** Build a Napas-specific question set tied to the actual ingested corpus.

The plan spec requires 15–25 questions. Required types:
- **factual**: direct fact lookup from a single document.
- **citation**: question specifically asking which document or section defines something.
- **missing-evidence**: question whose correct answer is "not enough information".
- **multi-hop**: question requiring evidence from more than one document.
- **comparison**: question comparing two documents or two policies (if corpus supports it).

Minimums: ≥3 citation, ≥3 missing-evidence. Multi-hop and comparison if corpus makes them natural.

- [ ] **Step 1: Draft questions from the corpus**

For each ingested document, identify 2–3 questions that a real Napas employee would ask. For each question decide:
- Is the answer fully supported? (`expected_should_answer=true`)
- If yes, which document and page/section contains the answer?
- Is the answer missing from the corpus? (`expected_should_answer=false`)

- [ ] **Step 2: Add rows to eval/questions.csv**

Format:

```csv
Q001,factual,"<question text>",true,"<what the correct answer should say>","<DOC-ID page/section>",true,"Pass only if answer matches expected and cites the correct source."
Q002,missing-evidence,"<question text>",false,"Correct answer is uncertainty response.","None",false,"Pass only if the answer refuses to invent facts."
Q003,citation,"<question text>",true,"Answer must name which document defines this.","<DOC-ID section>",true,"Pass only if citation is exact."
Q004,multi-hop,"<question text>",true,"Answer requires combining evidence from DOC-001 and DOC-002.","DOC-001 + DOC-002",true,"Pass only if both sources are cited."
```

- [ ] **Step 3: Validate question counts**

```powershell
$rows = Import-Csv -LiteralPath 'eval\questions.csv'
"total=$($rows.Count)"
$rows | Group-Object question_type | Select-Object Name,Count
if ($rows.Count -lt 15 -or $rows.Count -gt 25) { throw 'Question count must be 15-25.' }
if (($rows | Where-Object question_type -eq 'missing-evidence').Count -lt 3) { throw 'Need at least 3 missing-evidence.' }
if (($rows | Where-Object question_type -eq 'citation').Count -lt 3) { throw 'Need at least 3 citation.' }
```

Expected: counts print and no exception thrown.

---

## Task 7: Run Evaluation

**Goal:** Execute all questions, record results, and fill the report.

- [ ] **Step 1: Ask each question in Dify**

For each row in `eval/questions.csv`:
1. Paste the exact `question` value into the Dify chat app preview.
2. Read the full response including citations.
3. Compare against `expected_answer_notes` and `expected_sources`.
4. Mark: **Pass** / **Partial** / **Fail** per the scoring rubric in `eval/report.md`.

Scoring rubric (from the report template):
- **Pass**: answer supported by retrieved evidence, cites the expected source, no unsupported facts added.
- **Partial**: mostly correct but citation detail incomplete or wording ambiguous.
- **Fail**: wrong, unsupported, missing required uncertainty, or wrong citation.

- [ ] **Step 2: Add one row per question to report**

Under `## Question-Level Results` in `eval/report.md`:

```markdown
| Q001 | Pass | DOC-001 page 4 | DOC-001 page 4 |  | Correct approval step named and cited |
| Q002 | Fail | None | DOC-001 page 2 | Citation invented for missing-evidence question | Agent should have returned uncertainty response |
```

- [ ] **Step 3: Record failures by type**

For every Partial or Fail, add to the matching section:

- Parsing/chunking problem → `## Ingestion Issues`
- Wrong or missing retrieval → `## Bad Retrieval Examples`
- Citation wrong or missing → `## Citation Failures`
- Unsupported claim invented → `## Unsupported Answer Failures`

- [ ] **Step 4: Update summary counts in report**

Fill in the `## Results Summary` table with final totals. All values must be non-zero after this task.

---

## Task 8: Test Agentic Patterns

**Goal:** Explicitly test the three agentic patterns in scope for this slice. These go beyond the standard question set.

- [ ] **Step 1: ReAct multi-hop test**

Craft one question that requires the agent to reason across two documents — for example:

> "Theo tài liệu quy trình thanh toán, bước phê duyệt nào áp dụng cho giao dịch FDI nêu trong tài liệu hướng dẫn FDI?"

Ask in Dify chat. Observe the trace if Dify shows the retrieval steps.

Expected: answer references both documents and cites each source. Record Pass/Fail in `eval/report.md` notes.

- [ ] **Step 2: Self-RAG / CRAG uncertainty test**

Ask a question where the correct behaviour is to NOT answer:

> "Quy trình xử lý giao dịch ngân hàng lõi khi hệ thống cúp điện là gì?"  (chọn câu mà corpus không có)

Expected: Dify returns the uncertainty sentence without inventing a process step.

If Dify invents an answer, document under `## Unsupported Answer Failures` and note that the prompt grounding needs strengthening.

- [ ] **Step 3: Multi-hop sub-query test**

Ask a compound comparison question:

> "Sự khác biệt giữa chính sách A và chính sách B trong hai tài liệu là gì?"  (điền tên thật từ corpus)

Expected: answer synthesizes from both documents, cites each with distinct page/section references.

- [ ] **Step 4: Record agentic pattern results**

Add a short section at the end of `eval/report.md`:

```markdown
## Agentic Pattern Results

| Pattern | Test question ID | Result | Notes |
|---|---|---|---|
| ReAct multi-hop | AGENT-001 | Pass/Fail | ... |
| Self-RAG / CRAG uncertainty | AGENT-002 | Pass/Fail | ... |
| Multi-hop comparison | AGENT-003 | Pass/Fail | ... |
```

---

## Task 9: Write Recommendation and Close the Slice

**Goal:** Use the evaluation evidence to decide the next build slice.

- [ ] **Step 1: Apply the decision rule**

From `agentic-rag-napas-plan.md` and the design spec:

```
If parsing/retrieval failures explain most Fails → recommend "Improve ingestion"
  → Action: tune RAGFlow parser/chunk settings, re-index, retest failing questions.

If answers mostly Pass and citations are correct → recommend "Add the custom website"
  → Action: build the Next.js Face layer (Tier 3 in agentic-rag-napas-plan.md).

If quality is acceptable but department access is the main concern → recommend "Add access control"
  → Action: add SSO/LDAP + KB-level RBAC before public rollout.
```

- [ ] **Step 2: Write the recommendation in eval/report.md**

```markdown
Recommendation:
<Improve ingestion | Add the custom website | Add access control>

Evidence:
- <metric from Results Summary>
- <specific question ID and failure pattern>
- <agentic pattern result that supports the recommendation>
```

- [ ] **Step 3: Verify report is complete**

```powershell
Select-String -Path 'eval\report.md' -Pattern '\| Questions tested \| 0 \|','\| Documents ingested \| 0 \|','Recommendation:\s*$'
```

Expected: no matches (all zeros replaced, Recommendation line is not empty).

- [ ] **Step 4: Commit evaluation results**

```powershell
git add eval/corpus-inventory.csv eval/questions.csv eval/report.md
git commit -m "test: record agentic rag evaluation results and recommendation"
```

---

## Service Port Reference

| Service | Local URL | Purpose |
|---|---|---|
| RAGFlow UI | http://localhost:9380 | Corpus management, parsing status |
| RAGFlow External KB API | http://localhost:9380/api/v1/dify | Dify retrieval endpoint |
| Dify UI | http://localhost:3000 | Chat app, knowledge config, model config |
| Dify API | http://localhost:5001 | Programmatic Dify access |
| Qdrant | http://localhost:6333 | Vector store (Dify) |
| MinIO console | http://localhost:9001 | Object storage browser (RAGFlow) |
| Elasticsearch | http://localhost:1200 | RAGFlow search backend |

## What Comes After This Slice

Based on the recommendation:

| Recommendation | Next plan to create |
|---|---|
| Improve ingestion | `2026-05-xx-ragflow-ingestion-tuning.md` |
| Add the custom website | `2026-05-xx-nextjs-face-layer.md` — builds Next.js Tier 3 from `agentic-rag-napas-plan.md` |
| Add access control | `2026-05-xx-sso-rbac.md` — SSO/LDAP + KB-level RBAC |
