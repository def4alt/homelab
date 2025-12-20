---
name: paperless-openwebui-rag
description: Deploy Open WebUI + Ollama RAG for Paperless docs
---

# Plan

Stand up a lightweight, GitOps-managed RAG stack in k3s that pulls text directly from the Paperless API, embeds it with `embeddinggemma`, and serves queries via Open WebUI backed by `gemma3:4b`. Focus is on minimal CPU-friendly components and a clean ingestion pipeline.

## Requirements
- Open WebUI deployed in k3s via GitOps.
- Ollama deployed in k3s with `gemma3:4b` and `embeddinggemma` available.
- Ingestion pulls document text from Paperless API (no manual exports).
- Vector store persists locally in the cluster (PVC-backed).
- RAG flow supports mostly German content.

## Scope
- In: k3s manifests, Open WebUI, Ollama, ingestion worker/job, Paperless API integration, persistence.
- Out: external SaaS LLMs, GPU acceleration, multi-user auth design changes.

## Files and entry points
- `apps/paperless/` (API endpoint, auth details)
- New app folder for Open WebUI (e.g., `apps/open-webui/`)
- New app folder for Ollama (e.g., `apps/ollama/`)
- New app folder for ingestion worker (e.g., `apps/paperless-rag/`)
- `clusters/home/overlays/apps/` for Flux wiring

## Data model / API changes
- Paperless API: read-only access for document text + metadata.
- Vector store: persisted embeddings + metadata (doc id, title, tags).

## Action items
[ ] Confirm Paperless API endpoint, auth method, and fields for full text/OCR content.
[x] Add Ollama deployment/service with PVC and preload `gemma3:4b` + `embeddinggemma`.
[x] Add Open WebUI deployment/service and wire it to the Ollama service.
[~] Implement ingestion worker (CronJob or Deployment) that polls Paperless, chunks text, embeds via Ollama, and upserts into a local vector store.
[~] Provision vector store PVC and configure Open WebUI RAG to use it.
[x] Add Flux kustomizations/overlays for the new apps.
[ ] Validate end-to-end: ingest -> query -> citations from Paperless docs.

## Testing and validation
- Verify ingestion logs show document fetch + embedding counts.
- Query a known document term in Open WebUI and confirm relevant excerpts.
- Confirm `gemma3:4b` and `embeddinggemma` are listed/healthy in Ollama.

## Risks and edge cases
- Paperless API limits/permissions might exclude OCR text.
- CPU-only embedding throughput could be slow; may need batching/backoff.
- Large docs may need chunking strategy tuned for German language.

## Open questions
- What is the Paperless base URL and auth mechanism (token/user/pass)?
- Preferred ingestion cadence (cron interval)?
- Should RAG include attachments and non-PDF text, or only OCR'd content?

## Progress updates
- 2025-12-20: Created `ai` namespace, added Ollama + Open WebUI deployments/services/PVCs, and wired Flux overlays for new apps.
- 2025-12-20: Added an Ollama prefetch Job for `gemma3:4b` and `embeddinggemma` to warm the model cache on first deploy.
- 2025-12-20: Added a Paperless sync CronJob that pulls document text via the Paperless API and optionally posts to Open WebUI if an API key is provided. A new `paperless-rag-secrets` SOPS secret is required for Paperless credentials.
- 2025-12-20: Default Open WebUI ingress hostname set to `llm.def4alt.com` with authentik forward-auth; update if a different hostname is preferred.
- 2025-12-20: Switched Paperless ingestion auth to API token; update `paperless-rag-secrets` to include a `paperless-token` key.
