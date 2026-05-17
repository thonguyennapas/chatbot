# Wiring RAGFlow + Dify Agentic RAG — Design

Date: 2026-05-16

## Purpose

Connect the Memory layer (RAGFlow) and Brain layer (Dify) of the Napas internal chatbot, ingest a real Napas-style corpus, and validate the three agentic patterns in scope for this slice:

1. **ReAct** — agent reasons before acting, handles multi-hop questions.
2. **Self-RAG / CRAG** — agent evaluates retrieval sufficiency; missing-evidence path returns an explicit uncertainty response.
3. **Multi-hop retrieval** — complex questions decomposed into sub-queries synthesized across documents.

This design is the second slice. It assumes the Windows-native infrastructure from `2026-05-16-windows-native-stack-scripts-design.md` is fully operational.

Full system context: `agentic-rag-napas-plan.md`.

## Scope

Included:
- RAGFlow dataset creation and corpus ingestion (manual upload via RAGFlow UI).
- Dify External Knowledge API connection to RAGFlow at `http://localhost:9380/api/v1/dify`.
- Dify chat app with grounded-answer prompt.
- Evaluation pack: `eval/corpus-inventory.csv`, `eval/questions.csv`, `eval/report.md`.
- Manual evaluation of 15–25 questions.
- Explicit tests for ReAct, Self-RAG, and Multi-hop patterns.
- Recommendation for the next build slice.

Excluded (future slices):
- Custom Next.js website (Face layer — Tier 3).
- SSO / LDAP / NextAuth integration.
- Department-level RBAC.
- Admin panel or automated upload pipeline.
- Event-driven workflows (Pattern 5).
- Tool Use + Action (Pattern 4).
- OpenRouter cost routing and fallback.
- Local confidential-data model routing.
- Automated RAGAS scoring.

## Architecture

```
corpus (PDF/DOCX)
    │
    ▼
RAGFlow UI (localhost:9380)
    │  layout-aware parsing → chunking → embedding
    ▼
RAGFlow dataset: napas-rag-quality-mvp
    │
    │  External Knowledge API
    │  POST /api/v1/dify/retrieval
    ▼
Dify chat app (localhost:3000)
    │  ReAct loop:
    │  1. Receive question
    │  2. Query RAGFlow (Top K=5, Score≥0.30)
    │  3. Evaluate retrieved evidence sufficiency (CRAG)
    │  4. Generate grounded answer with citations
    │  5. Return uncertainty if evidence insufficient
    ▼
Evaluator (human, this slice)
    │
    ▼
eval/report.md
```

## Connection Parameters

| Parameter | Value |
|---|---|
| RAGFlow External KB endpoint | `http://localhost:9380/api/v1/dify` |
| Dify → RAGFlow Top K | 5 |
| Dify → RAGFlow Score Threshold | 0.30 |
| Dify LLM | claude-sonnet-4-6 (preferred) or equivalent |
| Qdrant (Dify vector store) | `http://127.0.0.1:6333` |

## Corpus Constraints

From the design spec `2026-05-14-agentic-rag-napas-rag-quality-mvp-design.md`:
- 5–10 files, PDF and DOCX only.
- Policy, procedure, FAQ, or operational-process documents preferred.
- No confidential customer data, credentials, production logs, or PII.
- Explicit non-sensitive approval required per file.
- Excel-heavy documents deferred unless critical to the selected process area.

## Evaluation Pack Requirements

| File | Requirement |
|---|---|
| `eval/corpus-inventory.csv` | 5–10 rows, all `approved_non_sensitive=true`, ingestion status recorded |
| `eval/questions.csv` | 15–25 rows, ≥3 citation type, ≥3 missing-evidence type |
| `eval/report.md` | All summary counters non-zero, Recommendation line filled |

Question types:

| Type | Definition | Minimum |
|---|---|---|
| factual | Single-document direct fact lookup | — |
| citation | Asks which document/section defines something | 3 |
| missing-evidence | Correct answer is "not enough information" | 3 |
| multi-hop | Requires evidence from 2+ documents | 1 (if corpus supports) |
| comparison | Compares two policies or documents | optional |

## Agentic Pattern Acceptance Criteria

**ReAct multi-hop:** A question requiring evidence from two or more documents must produce an answer that cites each source with distinct document name and page/section references. A single-document citation is a Fail.

**Self-RAG / CRAG:** A question whose answer is absent from the corpus must produce the exact uncertainty sentence: "The provided documents do not contain enough information to answer this." An invented answer is a Fail.

**Multi-hop comparison:** A question comparing two documents or two policies must name both documents in the answer and cite both. Citing only one is a Partial.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| RAGFlow chunking splits tables across chunks | Wrong or incomplete evidence returned | Switch parser to naive layout; record in Ingestion Issues |
| Dify prompt ignored — agent invents answers | Unsupported-answer failures | Strengthen prompt; check LLM temperature setting |
| Top K too low — relevant chunk not retrieved | Missing-evidence failures on answerable questions | Increase Top K to 8 and retest; record in Bad Retrieval Examples |
| Score threshold too strict — good chunks filtered | Same as above | Lower threshold to 0.20 and retest |
| RAGFlow External KB API returns empty for all queries | Full evaluation blocked | Verify API key, dataset ID, and connectivity; check ragflow-api logs |
| Qdrant not running — Dify cannot embed | Dify API 500 errors | Confirm qdrant service is running and `runtime/dify/api/.env` has VECTOR_STORE=qdrant |

## Inputs Required Before Execution

- Explicit approval list of 5–10 non-sensitive PDF/DOCX files for the corpus.
- LLM API key available to configure in Dify (Anthropic, OpenRouter, or other provider).
- RAGFlow admin account (created on first login to `http://localhost:9380`).
- Dify admin account (created on first login to `http://localhost:3000`).
