# Minimal Homelab Configuration

## Purpose

Remove retired configuration and redundant overrides while preserving the current
single-node k3s behavior. Pin deployed charts and mutable application images so
that relying on chart defaults does not also mean accepting unreviewed upgrades.

## Scope

- Remove the retired Longhorn manifests and stale documentation.
- Remove Longhorn assumptions from shared Glance and Paperless PVCs and simplify
  their environment patches.
- Remove obsolete Flux v1 annotations and values that only restate safe defaults.
- Pin active Helm releases to the versions currently deployed on `perun`.
- Pin mutable image references to the digests currently running on `perun` and
  remove `Always` pull policies made unnecessary by immutable references.
- Validate all affected Kustomize overlays before Flux reconciliation.
- Inventory runtime leftovers separately; delete only clearly temporary debug
  resources, not retained application data or backups without explicit review.

## Non-Goals

- Replacing raw manifests with another templating layer.
- Removing resource limits, persistence, retention, authentication, monitoring
  discovery selectors, or k3s-specific component disablement.
- Reworking application architecture or storage backends.

## Plan

- [x] Audit repository references, Helm overrides, and mutable images.
- [x] Record current Helm chart versions and container image digests from `perun`.
- [x] Remove dead Longhorn and unused Pi-hole manifests and update documentation.
- [x] Normalize shared PVC bases and reduce environment-specific patches.
- [x] Remove obsolete or proven-redundant Helm values.
- [x] Pin active Helm charts and mutable application images.
- [x] Build all affected Kustomize overlays and run repository checks.
- [ ] Commit and push the GitOps changes, reconcile Flux, and verify workloads.
- [x] Audit runtime leftovers and clean only unambiguously temporary resources.

## Decisions

- Explicit singleton replica counts remain because they document intended topology.
- Storage classes, volume bindings, resource limits, ingress, authentication, and
  k3s monitoring exclusions remain explicit because they are operational policy.
- Immutable image digests are used when the running mutable tag does not reveal a
  trustworthy semantic version.
- Historical ExecPlans remain as operational history even when they reference
  components that have since been removed.

## Validation

- `git diff --check`
- Kustomize build for home and Hetzner overlays
- Flux reconciliation succeeds
- HelmReleases and Kustomizations report Ready
- Pods return to Ready with the pinned images
- Prometheus targets and blackbox probes remain healthy

## Progress Notes

- 2026-07-17: Audit found tracked Longhorn manifests, an unused Pi-hole Longhorn
  PVC, repeated Longhorn-removal patches, obsolete Authentik Flux annotations,
  nine unpinned active Helm charts, and multiple mutable image tags.
- 2026-07-17: Captured deployed Helm versions and image digests before editing.
- 2026-07-17: All active home and Hetzner application paths build successfully.
  Removed an unowned, failed 44-day-old JuiceFS recovery-check pod.
- 2026-07-17: After explicit approval, removed seven Released Longhorn PVs and 55
  GiB of retired replica data. No Bound Longhorn PVs or other non-running pods
  existed; the node remained Ready and disk utilization fell from 83% to 77%.
- 2026-07-17: Post-reconciliation observability checks found all targets and 17
  probes healthy, but exposed a pre-existing invalid Telegram message template.
  Replaced the unsupported conditional and validated the decrypted configuration
  successfully with `amtool check-config`.
