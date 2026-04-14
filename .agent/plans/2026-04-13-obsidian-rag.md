# Obsidian Vault RAG for nanobot Implementation Plan

This ExecPlan must be maintained in accordance with `.agent/PLANS.md`.

**Goal:** Let nanobot search, read, and write notes in the already-populated Obsidian vault repo at `https://github.com/def4alt/vault`, using incremental embeddings from OpenRouter so repeated vault syncs only process new or changed note chunks.

**Architecture:** `apps/nanobot` will keep being the entry point, but the pod will also keep a local git-synced checkout of the vault and a small MCP server script. The MCP server will provide two kinds of tools: exact note file access for reading and writing Markdown files, and semantic search over an incremental local index built from note chunks. The index will store chunk hashes and embeddings so only new or changed chunks are re-embedded; unchanged chunks remain untouched across syncs.

**Tech Stack:** Kubernetes manifests in `apps/nanobot`, Flux overlay in `clusters/home/overlays/apps/nanobot.yaml`, Python 3.12, `nanobot-ai`, the MCP Python SDK, OpenRouter embeddings with `qwen/qwen3-embedding-8b`, git-sync or a simple git sidecar for the vault checkout, and SQLite for the local index cache.

---

## Purpose / Big Picture

After this change, nanobot will be able to treat the Obsidian vault as the user’s knowledge base. A question such as “what did I decide about backups?” can trigger semantic search over the vault, then exact file reads for the matching notes, and the answer can cite the relevant note paths. Nanobot will also be able to create or update notes directly inside the vault through a controlled file-writing tool, so the same system can capture new knowledge and answer questions from it later.

The user should be able to see the feature working by restarting the `nanobot` workload, asking nanobot to search the vault, and observing that only changed note chunks are re-embedded after a vault sync instead of the whole repository.

## Progress

- [x] (2026-04-13 00:00Z) Read the repo layout, the existing `apps/nanobot` manifests, and the nanobot memory and MCP documentation.
- [x] (2026-04-13 00:45Z) Added a vault sync initContainer and sidecar so the `nanobot` pod now keeps a local checkout of `def4alt/vault` under `/data/home/vault`.
- [x] (2026-04-13 00:45Z) Added a ConfigMap-mounted MCP server script that reads and writes vault files, chunks Markdown, stores a local SQLite cache, and only re-embeds changed chunks.
- [x] (2026-04-13 00:45Z) Wired the nanobot runtime config to launch the vault MCP server and expose search and note-editing tools.
- [x] (2026-04-13 00:55Z) Validated YAML syntax and compiled the embedded MCP script locally.
- [x] (2026-04-13 01:10Z) Fixed a rollout blocker where the first init image tag (`alpine/git:2.45.3`) did not exist, so the pod could pull from a known-good Alpine base image instead.
- [x] (2026-04-13 01:25Z) Added a GitHub PAT key to `apps/nanobot/secrets/nanobot-secrets.sops.yaml` and switched the vault clone to use authenticated GitHub URLs.
- [x] (2026-04-13 01:40Z) Fixed the MCP launch command to use the nanobot venv Python so the `mcp` module is actually available when the server starts.
- [x] (2026-04-13 01:55Z) Increased the Obsidian MCP tool timeout to give the first index/session more room to finish.
- [x] (2026-04-13 02:05Z) Added a vault-ready marker and taught the indexer to no-op until the clone is complete, so an early refresh cannot delete or rebuild the cache.
- [x] (2026-04-13 02:15Z) Added a managed SOUL.md block so nanobot’s system prompt now tells it to prefer Obsidian for durable knowledge and note capture.
- [x] (2026-04-13 02:25Z) Tightened the Obsidian policy to answer from the first strong hit and reduced the default search fan-out so note questions stop exploring so aggressively.
- [x] (2026-04-13 02:35Z) Switched the main chat provider from the rate-limited Minimaxi free model to Venice AI using `google-gemma-4-31b-it`.
- [x] (2026-04-13 02:55Z) Removed vault resync from the hot `search_notes` path, added a background sync loop, and lowered the default Obsidian fan-out to one result so note lookups return faster.
- [x] (2026-04-13 03:05Z) Passed `OPENROUTER_API_KEY` and the Obsidian embedding settings explicitly into the MCP subprocess, because the stdio launcher only inherits a narrow safe environment by default.
- [ ] Validate the end-to-end flow against the live cluster by syncing the vault, indexing a few notes, running a semantic query, and confirming that unchanged chunks are not re-embedded.

## Surprises & Discoveries

- Observation: `apps/nanobot` already has a persistent PVC and writes its runtime config on startup, which makes it a good host for both the vault checkout and the local index cache.
  Evidence: `apps/nanobot/deployment.yaml` mounts the `nanobot-data` PVC and writes `/data/home/.nanobot/config.json` before starting `nanobot gateway`.

- Observation: An initContainer was the simplest way to avoid a startup race between the vault checkout and the MCP server.
  Evidence: the pod now clones `https://github.com/def4alt/vault` before the main container starts, while the sidecar keeps it refreshed afterwards.

- Observation: The first choice of git image tag was invalid and blocked the rollout.
  Evidence: kubelet reported `docker.io/alpine/git:2.45.3: not found`, so the pod stayed in `Init:ImagePullBackOff` while the old nanobot pod continued running.

- Observation: The vault repository needs authentication from inside the cluster.
  Evidence: the init container reported `fatal: could not read Username for 'https://github.com'`, which is why the deployment now injects `github-pat` from `nanobot-secrets`.

- Observation: The MCP server must be launched with the venv interpreter, not the container’s system Python.
  Evidence: nanobot logged `ModuleNotFoundError: No module named 'mcp'` until the config pointed the MCP server at `/data/home/.nanobot/venv/bin/python`.

- Observation: A refresh that runs before the vault checkout is complete can accidentally behave like a full resync.
  Evidence: when the pod restarted and the indexer ran too early, the cached file rows were treated as stale and the next refresh had to rebuild embeddings; the new vault-ready marker prevents that path.

- Observation: nanobot already maintains a `SOUL.md` file in its workspace, so the cleanest prompt change was to append a managed block rather than replace the whole file.
  Evidence: `kubectl exec` against the running pod showed `/data/home/.nanobot/workspace/SOUL.md` already existed before this change.

## Decision Log

- Decision: Keep the vault as a git-synced checkout inside the `nanobot` pod instead of introducing a separate synchronization service.
  Rationale: This reuses the existing persistent volume and keeps the first implementation small and observable.
  Date/Author: 2026-04-13 / Codex

- Decision: Use a local MCP server for both note file access and semantic search instead of introducing a separate web API.
  Rationale: nanobot already supports MCP tools, so this keeps the integration direct and avoids another network hop.
  Date/Author: 2026-04-13 / Codex

- Decision: Re-embed by chunk hash, not by whole-vault sync.
  Rationale: This preserves embeddings for unchanged note chunks and prevents a full reindex when only one note changes.
  Date/Author: 2026-04-13 / Codex

- Decision: Use SQLite for the first index cache.
  Rationale: The vault index is local to the pod, does not need multi-user database access, and SQLite keeps the first implementation easy to ship and debug.
  Date/Author: 2026-04-13 / Codex

- Decision: Mount the MCP server as a ConfigMap file and use an initContainer plus a refresh sidecar for vault sync.
  Rationale: The script stays readable and reviewable in git, while the initContainer guarantees the vault exists before nanobot starts and the sidecar keeps it current afterwards.
  Date/Author: 2026-04-13 / Codex

- Decision: Store the GitHub PAT in `apps/nanobot/secrets/nanobot-secrets.sops.yaml` under the key `github-pat` and feed it into both git containers.
  Rationale: Reusing the existing nanobot secret keeps the auth material in the same SOPS-managed location as the other nanobot credentials.
  Date/Author: 2026-04-13 / Codex

- Decision: Launch the MCP server with `/data/home/.nanobot/venv/bin/python`.
  Rationale: nanobot installs the `mcp` package into its venv at startup, so the MCP server must use that interpreter to import the module successfully.
  Date/Author: 2026-04-13 / Codex

- Decision: Set the Obsidian MCP `toolTimeout` to 900 seconds.
  Rationale: the first vault sync and embedding pass can take longer than a few minutes, so the tool budget should not expire before the initial index is ready.
  Date/Author: 2026-04-13 / Codex

- Decision: Add a vault-ready marker file and teach the indexer to no-op until that marker exists.
  Rationale: this prevents a refresh from treating an incomplete checkout as a deleted vault and wiping the SQLite cache.
  Date/Author: 2026-04-13 / Codex

- Decision: Manage the Obsidian instruction as a marked block inside `SOUL.md` instead of replacing the whole file.
  Rationale: that keeps the default nanobot personality intact while layering on the Obsidian-specific behavior, and it lets future restarts update only the managed section.
  Date/Author: 2026-04-13 / Codex

- Decision: Lower the default Obsidian search fan-out to three results and tell nanobot to stop after the first strong note hit.
  Rationale: the previous behavior kept exploring with extra filesystem searches and made note questions feel too slow.
  Date/Author: 2026-04-13 / Codex

- Decision: Move the main chat provider from the free Minimaxi model to Venice AI with `google-gemma-4-31b-it`.
  Rationale: the logs showed repeated upstream 429 rate limits on `minimax/minimax-m2.5:free`, so the assistant needed a less-throttled default model.
  Date/Author: 2026-04-13 / Codex

- Decision: Make `search_notes` query-only and run vault sync in a background loop instead of on every search.
  Rationale: the previous hot-path sync forced a full vault scan before every retrieval request, which made note lookups much slower than necessary.
  Date/Author: 2026-04-13 / Codex

- Decision: Pass embedding and vault settings explicitly to the Obsidian MCP subprocess.
  Rationale: the MCP stdio launcher does not inherit arbitrary pod environment variables, so the search tool would otherwise lose `OPENROUTER_API_KEY` and fail before it can build embeddings.
  Date/Author: 2026-04-13 / Codex

## Outcomes & Retrospective

This section will be filled in after the implementation is complete. It should explain whether the final behavior matches the purpose above, what tradeoffs were accepted, and what remains to be improved later.

## Context and Orientation

`apps/nanobot` is the current home of the assistant workload. `apps/nanobot/deployment.yaml` launches `nanobot gateway`, `apps/nanobot/configmap.yaml` currently holds the model name, and `apps/nanobot/secrets/nanobot-secrets.sops.yaml` already carries the OpenRouter key used by the assistant. The `clusters/home/overlays/apps/nanobot.yaml` Flux object points at that app directory, so any manifest changes under `apps/nanobot` are picked up by Flux after commit.

The new vault source is the public git repository `https://github.com/def4alt/vault`. The vault is the human-edited Obsidian knowledge base. In this plan, a “chunk” means a small semantic piece of a Markdown note, usually a heading section or paragraph, that can be embedded independently. A “chunk hash” means a stable digest of the normalized chunk text, used to decide whether that chunk needs a new embedding.

## Plan of Work

First, change the `nanobot` pod so it can see two writable paths on the same persistent volume: the existing `.nanobot` runtime directory and a sibling `vault` directory for the git checkout. Add a lightweight git sync container that keeps `https://github.com/def4alt/vault` cloned into that `vault` path and refreshes it periodically. This gives the whole system a stable local copy of the notes without changing how Flux manages the pod.

Second, add a dedicated MCP server script for vault access and retrieval. Place the script in `apps/nanobot` as a ConfigMap-mounted file or equivalent mounted artifact, and make it implement note reading, note writing, note appending, index refresh, and semantic search. The script should store its local cache under `/data/home/.nanobot`, scan only Markdown files, split notes into chunks, hash each normalized chunk, and only call OpenRouter embeddings for chunks whose hash is new or changed. Removed chunks should be deleted from the local cache.

Third, update the runtime config generation in `apps/nanobot/deployment.yaml` so nanobot launches the new MCP server as a local tool provider and can call the vault tools during chat. Use the existing OpenRouter secret and add an environment-driven embedding model defaulting to `qwen/qwen3-embedding-8b`. Preserve the current chat gateway behavior and do not introduce a new network-facing service.

Finally, validate the change by checking the updated manifests, starting the pod, and exercising at least one search and one write action against the vault. Confirm that a second sync with no note changes does not re-embed existing chunks, while editing a single Markdown note only re-embeds the changed chunks from that note.

## Concrete Steps

Work from the repository root `/Users/def4alt/source/homelab`.

1. Edit the nanobot Kubernetes manifests and add the vault sync and MCP server wiring.
2. Add or update the vault MCP server script so it can maintain the local index cache and answer semantic search requests.
3. Run a manifest check if available, or at minimum inspect the rendered YAML and the generated runtime config for obvious syntax errors.
4. Restart or reconcile the `nanobot` Flux object and verify the pod starts with the new sidecar and MCP tools.
5. Run one search query, inspect the returned note paths, and then change a single note in the vault to confirm only that note’s changed chunks are re-embedded.

Expected success output after the deployment step should include the `nanobot` pod running normally and the vault checkout present at `/data/home/vault` inside the pod. Expected success output after the search step should include a result list with note paths and snippets from the Obsidian vault.

## Validation and Acceptance

The change is complete when nanobot can answer a question by searching the Obsidian vault, reading the matching note files, and citing the note paths in its response. It is also complete when a vault sync that does not change any Markdown files results in zero new embeddings, and a small edit to a single note results in embeddings being generated only for the modified chunks from that note.

A novice should be able to verify the behavior by checking the pod logs, asking nanobot to search for a known phrase from the vault, and then making a tiny edit to a note and confirming the index updates only the changed chunk set.

## Idempotence and Recovery

The git sync step should be safe to re-run because it is only maintaining a checkout of a public repository. The index cache should be safe to delete and rebuild from the vault checkout if it becomes corrupted. If the MCP server fails to start, the pod should still be recoverable by removing the new config and restarting the `nanobot` workload.

## Artifacts and Notes

The most important evidence to capture during implementation will be the final pod spec, the generated nanobot config, and a short search result transcript showing note paths from the vault. Keep those outputs concise and only capture what proves the new behavior.

## Interfaces and Dependencies

The implementation should leave `apps/nanobot/deployment.yaml` responsible for launching the main gateway, the vault sync container, and the runtime config generation. The MCP server script should expose at least these tools: `search_notes(query, top_k)`, `read_note(path)`, `write_note(path, content)`, `append_note(path, content)`, and `refresh_index()`.

The index cache should persist under `/data/home/.nanobot/obsidian-rag/` and should store enough metadata to detect changed chunks by hash, preserve existing embeddings for unchanged chunks, and remove entries for deleted chunks. The embedding client should call OpenRouter with the embedding model taken from `OBSIDIAN_EMBEDDING_MODEL`, defaulting to `qwen/qwen3-embedding-8b`.

Revision note: the implementation now uses an initContainer plus a git-sync sidecar instead of a single long-lived clone process, and the MCP server is mounted from a ConfigMap so the logic stays reviewable in git.
