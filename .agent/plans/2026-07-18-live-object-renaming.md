# Live Kubernetes Object Renaming

## Purpose

Finish the manifest naming cleanup by replacing legacy host and storage migration
qualifiers in active Kubernetes object names. Preserve all application data while
recreating immutable PVs, PVCs, and CloudNativePG clusters under their canonical
names.

## Scope

- Remove the `perun-` and `-local` qualifiers from statically bound PV names.
- Remove `-local` from application PVC names where it is only a migration detail.
- Rename the Home Assistant, Immich, and JuiceFS CloudNativePG clusters and update
  their service consumers and backup schedules.
- Keep `manual-local` as the storage class name because it describes the storage
  implementation rather than a migrated object.
- Preserve existing hostPath directories for ordinary application volumes.
- Recover the three renamed PostgreSQL clusters from fresh verified backups into
  new canonical hostPath directories.

## Plan

- [x] Inventory all live PV, PVC, CloudNativePG, workload, and Flux states.
- [x] Create and verify fresh plugin backups for the three renamed databases.
- [x] Update manifests, application references, and encrypted connection URLs.
- [ ] Build every affected Kustomize path and review the rendered object map.
- [ ] Commit and push the GitOps changes after operator approval.
- [ ] Suspend affected Flux reconciliation and quiesce database clients.
- [ ] Preserve old database directories, then reconcile the canonical resources.
- [ ] Wait for database recovery and all dependent workload rollouts.
- [ ] Remove released legacy PVs and verify no legacy live object names remain.
- [ ] Verify Flux, pods, volumes, database backups, monitoring, and service probes.

## Decisions

- Fresh object-store recovery is used for CloudNativePG because Cluster and PVC
  names are immutable and direct adoption of renamed PostgreSQL data directories
  is not a supported migration mechanism.
- Legacy database directories remain available as a rollback source until the
  restored clusters and a new post-rename backup are verified.
- Ordinary hostPath volumes are rebound without copying their contents; their
  paths are unchanged and all PVs use the `Retain` reclaim policy.
- Recovery sources retain the former Barman server names because those are backup
  catalog identifiers, not active Kubernetes object names.

## Validation

- `kubectl kustomize --load-restrictor=LoadRestrictionsNone` for every affected app
- `git diff --check`
- All Flux Kustomizations and HelmReleases report Ready
- Every pod is Running and all containers are Ready
- Every active PVC and PV is Bound
- All CloudNativePG clusters report healthy and accept application connections
- Fresh post-rename backups complete for Home Assistant, Immich, and JuiceFS
- Prometheus has no down targets and all Blackbox Exporter probes succeed
- No active Kubernetes object name contains retired `perun-` or `-local` qualifiers
