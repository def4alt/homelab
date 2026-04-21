# Staggered Backups for Stateful Apps

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` updated as work proceeds.

## Purpose / Big Picture

The homelab has too many backup-related jobs landing at the same time, which creates avoidable IO bursts on `perun`. This change spreads backup/snapshot activity across the overnight window and assigns different frequencies based on app importance:

- **Daily**: Immich, Paperless, Kaneo, Nanobot
- **Weekly**: everything else with backup coverage
- **Window**: avoid `08:00-22:00`, keep jobs in the overnight slots

The outcome should be flatter storage load, fewer attach/mount spikes, and less contention with k3s/etcd.

## Progress

- [x] Plan written.
- [x] Update CNPG scheduled backups to stagger daily and weekly windows.
- [x] Reintroduce Longhorn recurring jobs for PVC-backed apps that need snapshot coverage.
- [x] Label PVCs so Longhorn assigns the right daily/weekly job group.
- [x] Add the missing Flux wiring for the Longhorn config overlay.
- [x] Validate manifests locally.

## Surprises & Discoveries

- Longhorn recurring jobs previously existed in this repo and were removed during the earlier backup cleanup.
- The old pattern used `RecurringJob` CRs plus PVC labels such as `recurring-job.longhorn.io/source: enabled` and `recurring-job-group.longhorn.io/default: enabled`.
- `apps/longhorn-config/` exists as an empty directory, so the recurring-job manifests needed to be restored and wired back into Flux.
- Authentik and JuiceFS did not yet have CNPG backup object stores or plugin wiring, so those had to be added alongside the new weekly schedules.

## Decision Log

- Decision: Keep database backups on CloudNativePG and use Longhorn recurring snapshots only for PVC-backed app data.
  Rationale: The cluster no longer has a Longhorn backup target configured, and re-enabling off-node Longhorn backups would add more IO than necessary.
- Decision: Use per-app groups rather than one shared Longhorn group.
  Rationale: App-specific groups make it easy to stagger backup/snapshot times across the night and avoid clumping.
- Decision: Give paperless two layers of protection.
  Rationale: Paperless has both a CNPG database and a stateful PVC, so both should get scheduled coverage.
- Decision: Add missing CNPG backup object stores for Authentik and JuiceFS.
  Rationale: The new weekly schedules need the same Barman plugin wiring as the existing DB-backed apps.

## Context and Orientation

Relevant existing files:
- `apps/immich/scheduled-backup.yaml`
- `apps/paperless/scheduled-backup.yaml`
- `apps/kaneo/scheduled-backup.yaml`
- `apps/home-assistant/scheduled-backup.yaml`
- `apps/executor/scheduled-backup.yaml`
- `apps/authentik/postgres-cluster.yaml`
- `apps/juicefs/postgres-cluster.yaml`
- `apps/authentik/barman-objectstore.yaml`
- `apps/juicefs/barman-objectstore.yaml`
- `apps/paperless/pvc.yaml`
- `apps/nanobot/pvc.yaml`
- `apps/pi-hole/pvc.yaml`
- `apps/glance/pvc.yaml`
- `apps/longhorn-config/recurringjobs.yaml`
- `clusters/home/overlays/kustomization.yaml`
- `clusters/home/overlays/infra/longhorn.yaml`
- `clusters/home/overlays/infra/longhorn-config.yaml`

## Plan of Work

### 1) Stagger CNPG scheduled backups

Use daily jobs for the highest-change DBs and weekly jobs for the rest:

- Daily:
  - Immich DB
  - Paperless DB
  - Kaneo DB
- Weekly:
  - Authentik DB
  - Home Assistant DB
  - Executor DB
  - JuiceFS metadata DB

Keep the backups inside the overnight window and spread them so they do not overlap.

### 2) Restore Longhorn recurring jobs for PVC-backed data

Add `RecurringJob` resources in `apps/longhorn-config/` for app data that still lives on Longhorn:

- Daily snapshot jobs:
  - Paperless storage PVC
  - Nanobot data PVC
- Weekly snapshot jobs:
  - Glance data PVC
  - Pi-hole PVCs

Use separate recurring-job groups per app so each app can have its own time slot.

### 3) Wire Longhorn config back into Flux

Add a Flux `Kustomization` for `apps/longhorn-config` and include it in the home overlay after `longhorn`.

### 4) Tag PVCs with the right job group

Add the Longhorn recurring-job labels back to the relevant PVCs so the new job groups attach to the correct volumes.

## Concrete Steps

1. Edit the CNPG backup schedules and add the missing weekly `ScheduledBackup` resources.
2. Add the missing CNPG object-store manifests and plugin wiring for Authentik and JuiceFS.
3. Restore `apps/longhorn-config/kustomization.yaml` and `apps/longhorn-config/recurringjobs.yaml`.
4. Add `clusters/home/overlays/infra/longhorn-config.yaml` and include it from `clusters/home/overlays/kustomization.yaml`.
5. Restore Longhorn recurring-job labels on the PVC manifests that should participate.
6. Run a local manifest build to catch schema issues before applying anything.

## Validation and Acceptance

- `kubectl kustomize clusters/home/overlays` succeeds.
- CNPG scheduled backups are staggered rather than clumped.
- Longhorn config reconciles through Flux.
- Relevant PVCs show the intended recurring-job labels.
- The overnight backup/snapshot windows do not overlap heavily.

## Rollback Plan

If the new schedule causes trouble, revert the schedule changes first and leave the previous backup cadence in place. If the Longhorn recurring jobs create more pressure than expected, remove the `apps/longhorn-config` overlay and PVC labels while keeping the CNPG changes.

## Outcomes & Retrospective

- CNPG backups are now split into daily and weekly windows.
- Longhorn recurring snapshots are restored for the PVC-backed apps that still need them.
- The home overlay now includes the Longhorn config overlay again.
- `kubectl kustomize clusters/home/overlays` succeeds locally.
