# Remove Longhorn + Restic Backups, Keep CNPG Only

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with that file.

## Purpose / Big Picture

After this change, the homelab retains only CloudNativePG backups (via the barman plugin) and removes other backup paths. Longhorn recurring backup jobs, Longhorn S3 backup target configuration, and the Restic cron backup of Longhorn volume data will be removed from GitOps so that Flux stops reconciling them. The observable outcome is that the Restic CronJob no longer exists, Longhorn has no backup target configured, and Longhorn has no recurring jobs configured for snapshots or backups.

## Progress

- [x] (2025-02-14 22:00Z) Remove Restic resources and Flux wiring so the CronJob and credentials are no longer reconciled.
- [x] (2025-02-14 22:00Z) Remove Longhorn backup target configuration and credentials.
- [x] (2025-02-14 22:00Z) Remove Longhorn recurring jobs and related PVC annotations.
- [ ] (pending) Validate manifests and document verification checks.

## Surprises & Discoveries

None yet.

## Decision Log

- Decision: Remove both snapshot and backup recurring jobs from Longhorn to ensure only CNPG backups remain.
  Rationale: The user requested only CNPG backups, and recurring snapshots are a backup mechanism outside CNPG.
  Date/Author: 2025-02-14 / Codex

## Outcomes & Retrospective

Pending.

## Context and Orientation

Restic is configured in `apps/restic/` with a CronJob and a SOPS-encrypted secret. It is wired into Flux via `clusters/home/overlays/infra/restic.yaml` and referenced in `clusters/home/overlays/kustomization.yaml`.

Longhorn backup configuration lives in `apps/longhorn/helmrelease.yaml` under `values.defaultBackupStore`, and its backup credentials are stored in `apps/longhorn/secrets/backup-target-credentials.sops.yaml`. Longhorn recurring jobs are defined in `apps/longhorn-config/recurringjobs.yaml`. Several PVCs include Longhorn recurring job annotations (for example `apps/immich/pvc.yaml` and `apps/pi-hole/pvc.yaml`).

## Plan of Work

Remove the Restic app manifests and the Flux Kustomization that applies them. Remove the Longhorn default backup target and credential secret so Longhorn no longer syncs backups to S3. Remove the Longhorn recurring job manifests, and strip the Longhorn recurring job annotations from PVCs so the cluster no longer schedules snapshot/backup jobs for those volumes.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1) Delete Restic from GitOps:
   - Remove `apps/restic/` manifests (CronJob, kustomization, secret).
   - Remove `clusters/home/overlays/infra/restic.yaml`.
   - Remove `infra/restic.yaml` from `clusters/home/overlays/kustomization.yaml`.

2) Disable Longhorn S3 backup target:
   - Remove `values.defaultBackupStore` from `apps/longhorn/helmrelease.yaml`.
   - Remove `apps/longhorn/secrets/backup-target-credentials.sops.yaml` from the repo and any reference in `apps/longhorn/kustomization.yaml` if present.

3) Remove Longhorn recurring jobs and PVC annotations:
   - Delete `apps/longhorn-config/recurringjobs.yaml` or remove the backup/snapshot definitions.
   - Remove `recurring-job.*` annotations from PVC manifests that enable default recurring jobs.

4) Sanity-check manifests locally:
   - Run `kustomize build clusters/home/overlays` and expect no errors.

## Validation and Acceptance

After Flux reconciles, verify:

- The Restic CronJob is gone: `kubectl -n infra get cronjob restic-backup` returns NotFound.
- Longhorn no longer shows a backup target configured in its UI or settings.
- Longhorn recurring jobs list is empty.

## Idempotence and Recovery

Removing these resources is safe to re-apply; Flux will converge to the new state. If backups need to be restored later, the manifests can be reintroduced and reconciled.

## Artifacts and Notes

None yet.

## Interfaces and Dependencies

This change interacts with Flux Kustomizations, Longhorn Helm values, and PVC annotations. No new dependencies are introduced.

Change note: Initial plan created to remove Restic + Longhorn backups and leave CNPG backups only.
Change note: Marked removal steps complete after deleting Restic resources, Longhorn backup config, and recurring job annotations.
