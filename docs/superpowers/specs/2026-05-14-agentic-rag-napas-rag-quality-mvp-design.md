# Agentic RAG Napas RAG Quality MVP Design

Date: 2026-05-14

## Purpose

Build the first proof slice for the Napas internal chatbot by validating whether the proposed RAGFlow + Dify stack can produce trustworthy answers from real Napas-style documents.

The goal is not to build the final user-facing product. The goal is to prove answer quality, source grounding, citation behavior, and uncertainty handling before investing in the custom website, access control, admin features, or enterprise routing.

## First Build Decision

Use the Thin Vertical RAG Proof approach:

- Run RAGFlow locally in Docker as the document engine.
- Run Dify locally in Docker as the orchestration and chat layer.
- Ingest 5-10 real, non-sensitive PDF/DOCX documents.
- Connect Dify to RAGFlow through the External Knowledge API.
- Create one Dify chat app for testing.
- Evaluate answers against a fixed question set with expected evidence.

This is the first build because it tests the riskiest assumption: whether the memory and brain layers can answer accurately from Napas-style documents with usable citations.

## Scope

Included:

- Local Docker deployment of RAGFlow and Dify.
- Manual document ingestion into RAGFlow.
- One RAGFlow knowledge base containing selected PDF/DOCX documents.
- One Dify chat app connected to that knowledge base.
- A grounded-answer prompt requiring citations and uncertainty when evidence is missing.
- A small evaluation pack and manual evaluation report.

Excluded:

- Custom Next.js website.
- Upload pipeline from a custom UI.
- SSO, LDAP, or NextAuth integration.
- Department-level RBAC.
- Admin panel.
- Event-driven workflows.
- API gateway integration.
- OpenRouter cost routing and fallback policy.
- Local confidential-data model routing.
- Automated nightly re-indexing.

## Architecture

The MVP has two runtime components:

1. RAGFlow
   - Parses PDF/DOCX documents.
   - Chunks and embeds document content.
   - Stores retrieval data in its built-in retrieval layer.
   - Exposes an External Knowledge API endpoint for Dify.

2. Dify
   - Hosts the chat app used for testing.
   - Queries RAGFlow as the external knowledge source.
   - Uses the configured LLM to generate answers from retrieved evidence.
   - Applies prompt rules for citations, grounding, and uncertainty.

The first MVP uses Dify's built-in UI for testing. Users should not interact with a custom website in this phase.

## Data Flow

### Ingestion

1. Admin selects 5-10 real, non-sensitive PDF/DOCX documents.
2. Admin uploads the documents into RAGFlow.
3. RAGFlow parses, chunks, embeds, and indexes the documents.
4. Any parsing or chunking issue is recorded as an ingestion issue.

For this MVP, ingestion is manual through RAGFlow. No custom upload UI or automated ingestion pipeline is required.

### Question Answering

1. User asks a question in the Dify chat app.
2. Dify queries the RAGFlow knowledge base through the External Knowledge API.
3. RAGFlow returns relevant chunks with source metadata.
4. Dify generates an answer using only retrieved evidence.
5. Dify includes citations for supported claims.
6. If evidence is insufficient, Dify says the documents do not contain enough information.

The MVP should keep agent behavior constrained to retrieve, answer, cite, and express uncertainty. Tool actions, scheduled jobs, proactive workflows, and internal API calls are out of scope.

## Corpus

The first corpus should use real internal documents that are explicitly approved as non-sensitive.

Document constraints:

- 5-10 files total.
- PDF and DOCX only.
- Prefer policy, procedure, FAQ, or operational-process documents.
- Avoid confidential customer data, credentials, production logs, and personally identifiable information.
- Avoid Excel-heavy test cases in this first milestone unless they are critical to the selected process area.

Each document should be tracked with:

- File name.
- Document type.
- Business topic.
- Approximate page count.
- Owner or source team, if available.
- Any known parsing concerns.

## Prompt Requirements

The Dify app prompt should require:

- Answer only from retrieved document evidence.
- Cite the relevant source document and page or section when available.
- Separate direct evidence from interpretation.
- Do not invent policy, deadlines, thresholds, names, or process steps.
- If evidence is missing or ambiguous, say that the provided documents do not contain enough information.
- If documents conflict, identify the conflict and cite both sources instead of choosing silently.

## Evaluation Pack

Create a small evaluation pack in the repo, expected under `eval/`.

The pack should contain:

- `eval/questions.csv` with 15-25 test questions.
- `eval/report.md` for the manual evaluation results.
- Expected answer notes for each question.
- Expected source document and page or section for each question.
- A marker for questions where the correct response is "not enough information."
- At least 3 citation-focused questions.
- At least 3 missing-evidence questions.
- Optional: 2-3 comparison questions across documents, only if the corpus naturally supports them.

The first version can be manual and file-based. Automated RAGAS or scripted scoring is not required for the first build.

## Acceptance Criteria

The MVP is acceptable when:

- RAGFlow and Dify run locally through Docker.
- Dify can query the RAGFlow knowledge base through the External Knowledge API.
- The Dify chat app answers simple factual and process questions from the corpus.
- Answers cite the correct source document and page or section when evidence exists.
- Answers avoid confident unsupported claims when evidence is missing.
- Missing-evidence questions receive an uncertainty response.
- Failed answers are recorded with the question, retrieved evidence, observed answer, and failure reason.
- Poor document parsing or chunking is recorded as an ingestion issue.

## Evaluation Report

The manual evaluation report should summarize:

- Total questions tested.
- Pass/fail count.
- Citation failures.
- Unsupported-answer failures.
- Missing-evidence failures.
- Bad retrieval or chunking examples.
- Documents that parsed poorly.
- Recommended next build slice.

The next build slice should be selected based on evidence:

- Improve ingestion if parsing or retrieval quality is weak.
- Add the custom website if the RAG quality loop is good enough.
- Add access control if the main blocker is safe internal rollout.

## Configuration Defaults

- Use default Docker ports unless RAGFlow and Dify conflict on the local machine; if they conflict, map Dify to a different host port and document it.
- Store local API keys and secrets in `.env` files that are not committed.
- Use the LLM provider and model already available to the implementer through Dify. Model choice is not part of the MVP success criteria as long as the model can follow citation and uncertainty instructions.
- Keep the corpus files outside git unless they are explicitly approved for repository storage.

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| PDF/DOCX parsing loses important layout or section metadata | Answers may cite weak or wrong evidence | Record ingestion issues and adjust parser/chunk settings before expanding scope |
| Dify answer generation ignores citation rules | Users may receive unsupported answers | Use stricter prompt instructions and evaluate missing-evidence cases |
| Corpus is too small or too easy | MVP may overstate readiness | Include realistic process questions and several missing-evidence tests |
| Non-sensitive document approval is unclear | Data-handling risk | Use only documents explicitly approved for local testing |
| Local Docker setup is unstable | Slows evaluation | Keep the deployment local and document exact setup steps and ports |

## Inputs Required Before Implementation

- Which exact PDF/DOCX documents will be used in the first corpus.
- Which local or hosted LLM credentials are available for Dify during the proof.
- Whether the selected documents may be referenced by filename in evaluation outputs.
