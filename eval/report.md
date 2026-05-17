# Napas RAG Quality MVP Evaluation Report

Date: 2026-05-14

## Environment

- RAGFlow URL: `http://localhost:8080`
- Dify URL: `http://localhost:3000`
- Dify app name: `Napas RAG Quality MVP`
- RAGFlow dataset name: `napas-rag-quality-mvp`
- RAGFlow commit: `09d45046e`
- Dify release tag: `1.14.0`
- Runtime note: RAGFlow UI uses host port `8080`; RAGFlow Elasticsearch `MEM_LIMIT` lowered to `2147483648` for Docker Desktop's current memory limit.
- LLM provider/model used in Dify:
- Evaluator:

## Corpus Summary

| Metric | Value |
|---|---:|
| Documents ingested | 0 |
| PDF files | 0 |
| DOCX files | 0 |
| Documents with parsing issues | 0 |

## Results Summary

| Metric | Value |
|---|---:|
| Questions tested | 0 |
| Pass | 0 |
| Partial | 0 |
| Fail | 0 |
| Citation failures | 0 |
| Unsupported-answer failures | 0 |
| Missing-evidence failures | 0 |
| Retrieval/chunking failures | 0 |

## Scoring Rubric

- Pass: answer is supported by retrieved evidence, cites the expected source, and does not add unsupported facts.
- Partial: answer is mostly correct but citation detail is incomplete or wording is ambiguous.
- Fail: answer is wrong, unsupported, missing required uncertainty, or cites the wrong source.

## Question-Level Results

| Question ID | Result | Expected source | Actual citation | Failure reason | Notes |
|---|---|---|---|---|---|

## Ingestion Issues

| Document ID | Issue | Impact | Action |
|---|---|---|---|

## Bad Retrieval Examples

| Question ID | Retrieved evidence problem | Impact | Action |
|---|---|---|---|

## Citation Failures

| Question ID | Expected citation | Actual citation | Action |
|---|---|---|---|

## Unsupported Answer Failures

| Question ID | Unsupported claim | Expected behavior | Action |
|---|---|---|---|

## Recommendation For Next Build Slice

Choose one:

- Improve ingestion if parsing or retrieval quality blocks trusted answers.
- Add the custom website if the RAG quality loop is strong enough for a user-facing proof.
- Add access control if quality is acceptable but document access is the main rollout concern.

Recommendation:

Evidence:
