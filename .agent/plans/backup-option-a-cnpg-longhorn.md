# ExecPlan: Option A Backups (CNPG + Longhorn to S3)

## Goal

Back up all stateful data for deployed services using:

- CNPG-native Postgres backups to S3-compatible object storage
- Longhorn-native volume backups (snapshots + backups) to S3-compatible object storage

## Scope (this repo)

Apps currently deployed via `clusters/home/overlays/kustomization.yaml`:

- `nextcloud`: PVCs + CNPG Postgres
- `immich`: PVC + CNPG Postgres
- `paperless`: PVC + CNPG Postgres
- `home-assistant`: PVC (chart) + CNPG Postgres
- `pi-hole`: PVCs
- `kan`: CNPG Postgres

Backup target inferred from existing config: Backblaze B2 (S3-compatible).

## Design

### CNPG

- Configure `Cluster.spec.backup.barmanObjectStore` for each database cluster.
- Use a single S3 credential Secret (SOPS-managed) per namespace (or shared if preferred later).
- Retention handled by CNPG/barman policies (to be set explicitly).

### Longhorn

- Configure Longhorn `backupTarget` + credentials Secret (SOPS-managed).
- Use Longhorn recurring jobs for:
  - `snapshot` (short retention, frequent)
  - `backup` (daily, longer retention)

## Implementation Steps

1. Add SOPS secrets for S3 credentials used by CNPG and Longhorn.
2. Update CNPG `Cluster` manifests to enable backups to B2 S3.
3. Update Longhorn HelmRelease values to set backup target and enable recurring jobs.
4. Document verification and restore drills.

## Verification

### CNPG

- Confirm backup config is accepted:
  - `kubectl -n <ns> get cluster <name> -o yaml | rg -n "backup|barmanObjectStore"`
- Confirm scheduled backups exist:
  - `kubectl -n <ns> get scheduledbackup`
- Confirm backups are being created:
  - `kubectl -n <ns> get backup`

### Longhorn

- Confirm settings:
  - `kubectl -n longhorn-system get settings.longhorn.io backup-target -o yaml`
  - `kubectl -n longhorn-system get settings.longhorn.io backup-target-credential-secret -o yaml`

## Restore Drill (high level)

- CNPG: restore into a new `Cluster` using an existing backup (separate ExecPlan when doing the first drill).
- Longhorn: restore a volume from a backup into a new PVC and attach it to a scratch Pod for verification.

## Progress Log

- 2025-12-18: ExecPlan created; implementation starting.
