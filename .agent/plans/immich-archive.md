# ExecPlan: Immich Cold Archive Job

## Goal

Free up the limited 500 GiB SSD by regularly archiving Immich media older than one year to cheaper object storage while keeping metadata searchable and recoverable, and ensuring Flux/Restic only back up the hot working set.

## Scope (this repo)

- Fleet: Immich running on k3s + Longhorn storage in the `immich` namespace.
- Supporting infrastructure: FluxCD overlays, Longhorn, existing Backblaze B2 bucket, Restic CronJob.
- Changes limited to declarative Kubernetes resources (CronJob, Secrets, ConfigMaps, scripts) and any required Helm/Flux values under `apps/immich`.

## Design

### Architecture

- **Source data** – Immich stores JPEG/MP4 files on Longhorn PVCs backed by the Restic CronJob, and metadata in CNPG Postgres (already backed up by Barman and ScheduledBackup).
- **Archive target** – Use the existing Backblaze B2 bucket (S3-compatible) to store compressed objects older than 1 year. Objects will be tagged so they can be rehydrated when needed.
- **Orchestration** – A Flux-managed Kubernetes `CronJob` in the `immich` namespace runs nightly/weekly, authenticates to Immich (API token or service account), scans for media older than 1 year, and offloads them via `rclone`/`aws s3 cp` to the B2 bucket. After a successful transfer, the job deletes the local file and optionally updates Immich metadata (e.g., mark as archived in the API).
- **Metadata tracking** – Store a ConfigMap/Custom Resource of archived batch IDs or exported manifest so restore jobs know where each file landed.
- **Restic impact** – The Restic CronJob (infra namespace) now records a smaller `/var/lib/longhorn` footprint, so daily snapshots stay within SSD capacity.

### Policies & Safety

- Archive only assets older than `now - 365d`. Optionally skip albums marked as “keep local” (if Immich metadata exposes tags).
- Keep a manifest (timestamp + object keys + app identifier) in ConfigMap once per archive run; rotate history via annotated ConfigMap versions.
- Keep a `retention` folder structure in B2 by year/month so retrieving a given month is easier.
- Run a dry-run option before deleting files.

## Implementation Steps

1. Add credentials Secret (SOPS-encrypted) that lets the archive job write to Backblaze B2 (reuse `cnpg-barman-s3` or create `immich-archive-b2` if separation preferred).
2. Create a helper container image (or use `python:slim` + scripts) that:
   - Authenticates to Immich via JWT/API token stored in a Secret (`apps/immich/secrets/...`).
   - Queries assets via Immich API & filters by `captureDate`/`createdAt`.
   - Uses `rclone`/`s3cmd` to upload eligible files to `s3://def4alt-homelab/archives/immich/YYYY/MM/`.
   - Updates Immich metadata via API to mark the asset as archived (or stores mapping in ConfigMap for manual review).
   - Deletes the file from the mounted PVC only after verifying upload success.
3. Add a `CronJob` (e.g., weekly) that mounts the Immich media PVC (read+write) and runs the helper script; configure resource limits and fail-fast guard clauses so it does not stomp on the live service.
4. Add a ConfigMap/Secret logging job results (counts/files). The job should emit metrics/logs and update annotations to show the last run/size archived.
5. Adjust Flux/Restic scheduling: ensure the Restic job runs after the archive job (e.g., Cron schedule respects chronology) so the newly freed space is captured.
6. Document the process in README/ExecPlan (this file), including how to restore archived items (download + `immich-cli restore`/upload via API).

## Verification

- On a staging cluster or scratch namespace:
  - Run the archiver with `DRY_RUN=1` to confirm it only sees >1-year-old assets.
  - Run the full job against a small dataset, confirm uploads appear in B2, and verify Immich metadata is updated.
- Monitor Restic CronJob sizes (`restic snapshots --tag longhorn`) to confirm new snapshots shrink by the archived amount.
- Check Immich UI/API returns archived assets with “restorable” metadata (link back to B2 object key).
 
## Restore Drill

- Flow:
 1. Pull the archived object from B2 (`restic` isn’t involved here – use `rclone`/`aws s3 cp` or https link).
 2. Upload via Immich API (or mount the volume, copy file back, and trigger a background metadata reconcile).
 3. Verify Immich lists the asset and copies the file onto the SSD again.

- Document fallback in case the helper job fails: keep the Manifest/ConfigMap around so manual restores can match file names to B2 keys.

## Risks & Mitigations

- **Data loss** if upload succeeds but delete runs before metadata updated: run copy->verify->update->delete pattern with retries and idempotent operations.
- **Job hitting API rate limits** – include exponential backoff and batching (page size/time window).
- **Archive job running while users upload** – schedule at low traffic (early morning) and use `readOnly` operations to snap older data.

## Progress Log

- 2026-01-03: ExecPlan created to cap SSD usage by archiving Immich cold data.
