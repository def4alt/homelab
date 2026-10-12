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
