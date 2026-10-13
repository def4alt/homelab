# Knowledge vault on perun

## Purpose

Replace the Notion "Personal Knowledge Hub" with a plain-Markdown git vault that Obsidian (Mac),
SilverBullet (browser/phone) and AI agents (Claude.ai, ChatGPT, Hermes via one MCP server) all use.
Retire the Obsidian LiveSync/CouchDB setup it replaces.

## Design

- Vault: `/srv/vault` on perun, a checkout of the private repo `def4alt/vault`. It is the single source
  of truth. Rules for agents live in the vault's `AGENTS.md`.
- `apps/vault` (namespace `vault`):
  - `silverbullet` 2.12.1-slim on `/srv/vault`, login via `SB_USER`, tailnet-only at `notes.def4alt.com`.
  - `vault-mcp` (github.com/def4alt/vault-mcp, FastMCP 4.1): `/mcp` over Streamable HTTP.
    Tailnet `vault.def4alt.com` accepts the Hermes bearer token. The public `mcp.def4alt.com`
    (Cloudflare tunnel, phase 4) accepts only GitHub OAuth for `def4alt`. OAuth state lives in
    the `vault-mcp-data` PV.
  - `vault-autocommit` CronJob (every 15 min): commits edits from Obsidian/SilverBullet and pushes
    to GitHub with a write deploy key. Agent writes through MCP are committed immediately.
- Syncthing: `/srv/vault` mounted at `/vault`, shared with the Mac only, `.git` ignored via `.stignore`.
- Backup: `apps/syncthing/vault-restic-backup.yaml`, nightly at 03:30 into the documents restic
  repository (tag `vault`), plus the GitHub remote.
- DNS: `notes` and `vault` are tailnet hostnames in `cloudflare/locals.tf`.
- Removed: `apps/livesync` (CouchDB + PVC), its namespace, overlay and the `couchdb` DNS record.

## Progress

- [x] 2026-10-12 Vault repo created, Notion + legacy vault + Letterboxd imported, verified, lint clean.
- [x] 2026-10-12 `/srv/vault` seeded on perun.
- [x] 2026-10-12 Secrets (SOPS): SilverBullet login, MCP bearer + JWT key, deploy key, GitHub OAuth client.
- [x] 2026-10-12 Reconciled; Syncthing `vault` folder shared with the Mac (`~/Vault`); tailnet DNS for `notes`
      and `vault` via OpenTofu; MCP smoke test over Tailscale (write + revert); restic snapshot verified.
- [x] 2026-10-12 Phase 4: GitHub OAuth app "def4alt vault MCP", `mcp.def4alt.com` tunnel route; Claude.ai,
      ChatGPT and Hermes connected. Bearer token verified refused on the public host.
- [x] 2026-10-12 Handover: vault README, weekly report-only lint CronJob (`apps/vault/lint.yaml`).

## Decisions

- Own MCP server instead of vault-cortex: guarded writes (no `confirmed`/`reviewed`, immutable
  sources, no credentials), commit per write, small surface; vault-cortex was pre-1.0 and churning.
- SilverBullet stays tailnet-only; no Authentik/Cloudflare Access needed.
- Restic reuses the documents repository so no new B2 credentials are needed.

## Lessons

- hostPath volumes ignore `fsGroup`: the MCP OAuth-state volume needs a root init container to chown it.
- OpenSSH refuses to run for a uid without a passwd entry, so the autocommit job uses the vault-mcp image.
- With the GitHub OAuth provider enabled, FastMCP's MultiAuth requires the `user` scope on every token;
  the static bearer verifier must grant it (fixed in vault-mcp 0.1.1).
- perun only pushes the vault; never push to `def4alt/vault` from elsewhere.
- On the Mac the vault must stay out of `~/Documents` (iCloud Drive), or Syncthing can't read it.

## v0.2 (2026-10-13): agents as collaborators, documents and shared files

- vault-mcp 0.2.0: layered package (domain: vault/lint/rules; infra: repo/documents/sharing; interfaces:
  app/ MCP server with mounted tool groups, worker). Tool annotations, typed output, prompts
  (ingest/ask/review/tidy/share), resources, Prometheus metrics on :9000, provider name in commits.
- Trust model: agents may write anywhere in the vault, confirm facts I confirm, batch (`apply_changes`),
  move with relinking, inspect `history` and `revert`. Hard limits: no secrets, sources immutable,
  schema-valid frontmatter, no `.git`.
- Documents: the whole `/srv/documents` tree is mounted read-only into vault-mcp; text extracted by the
  worker into `/var/lib/k8s-local-storage/vault/cache` (derived, rebuildable).
- Sharing: `files.def4alt.com` (nginx-unprivileged, `secure_link` + WebDAV PUT) serves signed links only.
  Uploads land in `/srv/documents/.inbox/<id>/`; `vault-worker` files them into `Agent/shared/<YYYY-MM>/`,
  de-duplicates by sha256 and writes a source note. All git writers share `flock .git/vault.lock`.
- Network: worker and nginx have no egress; vault-mcp may only reach public addresses (+ DNS).
- Monitoring: PodMonitor + PrometheusRule (`apps/vault/monitoring.yaml`). Monthly restore drill
  (`apps/syncthing/vault-restore-drill.yaml`).

## v0.3 (2026-10-13): flat files, SQLite index, consolidated tools, MCP Apps

- Files are flat: `blobs/<sha256[:16]>.<ext>` in the vault (immutable, gitignored, synced to the Mac,
  backed up by restic) plus one `files/<slug>.md` note each, in the same graph as notes. Uploads,
  URL fetches, ChatGPT attachments and the `Agent/inbox` Syncthing drop folder all go through one filing path.
  The v0.2 `Agent/shared/` files and their source notes were migrated.
- Search runs on a derived SQLite index (FTS5 unicode61, BM25, facets, links) in
  `/var/lib/k8s-local-storage/vault/cache/index.sqlite`, WAL mode, updated by the worker and after each
  MCP write; `vault-index --rebuild` recreates it. Text extracts are cached by content hash.
- MCP: 15 tools (ChatGPT-shaped `search`/`fetch`, scopes, filters, cursors, response_format, titles and
  annotations), upload and review widgets as MCP Apps with text fallbacks.
- nginx: `/b/` serves blobs under their original name (name is part of the signature); `/u/` answers CORS
  so the in-chat widget can upload.

### Lessons (v0.2/v0.3)

- nginx location regexes containing `{n,m}` must be quoted.
- A crash-looping rollout leaves `ProgressDeadlineExceeded`; Flux reports the Kustomization failed until a
  new rollout (`kubectl rollout restart`) clears it, even after the pod recovers.
- SQLite WAL readers need write access to the `-shm` file, so every process using the index mounts the
  cache read-write.
- The upload widget runs in a sandboxed iframe on the chat client's origin: uploads are cross-origin.
- `limit_except` switches disallowed methods to its own config before the rewrite phase, so an
  `if ($request_method = OPTIONS)` in the same location never runs for OPTIONS (preflights got 403).

## v0.3.1 (2026-10-13): agents with a shell move bytes themselves

`upload_link` (signed PUT + ready `curl`) and `curl -o` on links; a tailnet file host with a 4 GB limit.
Verified with a 40 MB PPTX through both hosts (dedupe, SHA-256 round trip).

## v0.4 (2026-10-13): the vault moves to zorya; six tools over a queryable vault

Decided with Andrii: store the vault on zorya with a light Docker Compose stack (not k3s), no backwards
compatibility (nobody depends on it yet), accept that Hermes runs on the same host in the `docker` group
(root-equivalent) and rely on tamper-resistant backups. Web research (2026-10-13) backed the shape: few
general tools + read-only SQL (Anthropic tool guidance, Cloudflare Code Mode, Supabase/Datasette SQL tools),
signed URLs for bytes (MCP has no file transfer yet), Caddy over Traefik without a Docker socket, a plain
systemd timer for pull-based deploys (Watchtower archived; doco-cd single-maintainer), Syncthing without `.git`.

- `hosts/zorya/vault/`: compose (Caddy 2.11.7, vault-mcp, worker, SilverBullet, Syncthing, restic job),
  Caddyfile, `deploy.sh` (systemd user timer: ff-only pull, SOPS decrypt with zorya's age key, compose up),
  runbook. One hostname `vault.def4alt.com`, DNS-only A/AAAA to zorya; Hetzner Cloud Firewall 80/443 only.
- vault-mcp 0.4.0: `search`/`fetch` (ChatGPT shapes), `sql` (mode=ro + authorizer + time limit + paging;
  FTS5 needs the `data_version` pragma), `write` (batches, moves, `base_rev`, `idempotency_key` as a commit
  trailer), `delete` (only destructive tool), `upload` (URL / ChatGPT file param / signed PUT + curl).
  Index schema v2 is the public data model (notes, documents, links, tags, files, fts, commits, problems).
  Caddy serves `/f` and `/d` from disk after `forward_auth` to `/_verify`; uploads stream to the server and
  answer with the file note. The worker took over autocommit, push and lint. Widgets, prompts, nginx gone.
- perun: `apps/vault` removed; Syncthing keeps a receive-only replica; perun prunes the shared restic
  repository (zorya's B2 key cannot delete) and runs the restore drill against zorya's snapshots.

Cutover order (the k8s Secrets disappear with the namespace): age key on zorya -> secrets into
`hosts/zorya/vault/secrets/*.sops` -> data copied perun -> zorya under the vault lock -> deploy -> DNS ->
reconnect clients -> push the perun removal.
