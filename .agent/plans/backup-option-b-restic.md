# ExecPlan: Option B Backups (Restic + Logical DB Dumps)

## Goal

Back up all stateful data for deployed services using:

- Restic (encrypted) for PVC-backed application data
- Postgres logical dumps (`pg_dump`) for CNPG-managed databases, stored in restic

## Scope (this repo)

Apps currently deployed via `clusters/home/overlays/kustomization.yaml`:

- `nextcloud`: PVCs + CNPG Postgres
- `immich`: PVC + CNPG Postgres
- `paperless`: PVC + CNPG Postgres
- `home-assistant`: PVC (chart) + CNPG Postgres
- `pi-hole`: PVCs
- `kan`: CNPG Postgres

## Non-goals

- PITR/WAL archiving (CNPG native backups) — user chose logical dumps instead
- Migrating/rewriting application manifests unrelated to backup

## Design

### Repositories

- One restic repository per namespace/app under the existing Backblaze B2 S3 bucket.
- Tag separation inside each repo:
  - `files` for PVC backups
  - `db` for database dump backups

### Scheduling

- Daily backups with `concurrencyPolicy: Forbid`.
- DB dump as an `initContainer` writing to `emptyDir`, then restic backs up the dump.

### Retention

- Apply `forget --prune` with `--tag` to scope retention to the job’s snapshot set.

## Implementation Steps

1. Add restic credential Secrets per namespace (SOPS-encrypted).
2. Add `CronJob` per namespace for PVC backups (mount relevant PVCs).
3. Add `CronJob` per CNPG cluster for logical dumps (pg_dump initContainer + restic).
4. Ensure pruning is tag-scoped and raise `ulimit -n` in restic jobs.

## Progress Log

- 2025-12-18: ExecPlan created; implementation starting.
- 2025-12-18: Plan paused; switching to Option A (CNPG + Longhorn) instead.
