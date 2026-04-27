# Homelab Mode Switching Implementation Plan

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

Add a GitOps-friendly two-mode setup for the home cluster so the user can switch between:
- `minecraft` mode: Minecraft stays up while selected app workloads are forced down
- `apps` mode: Immich, Paperless, Kaneo, and Hermes Agent stay up while Minecraft is forced down

The switch must be a small Git change that Flux can reconcile cleanly without fighting manual `kubectl scale` changes.

## Progress

- [x] (2026-04-27 00:00Z) Inspected the current Flux layout and confirmed `clusters/home/kustomization.yaml` currently points directly at `overlays`.
- [x] (2026-04-27 00:00Z) Confirmed the relevant app Kustomizations are Flux `Kustomization` resources under `clusters/home/overlays/apps/*.yaml`.
- [x] (2026-04-27 00:00Z) Created mode-aware app wrapper directories under `apps/modes/` that reuse existing app manifests and only patch replica counts.
- [x] (2026-04-27 00:00Z) Created `clusters/home/modes/apps` and `clusters/home/modes/minecraft` overlays that patch Flux app Kustomization `spec.path` fields.
- [x] (2026-04-27 00:00Z) Switched `clusters/home/kustomization.yaml` to use one active mode overlay instead of referencing `overlays` directly.
- [x] (2026-04-27 00:00Z) Added `scripts/switch-home-mode.sh` to edit the active mode path.
- [x] (2026-04-27 00:00Z) Validated both modes and the active cluster path with local Kustomize builds and syntax-checked the helper script.
- [x] (2026-04-27 00:00Z) Added `docs/operations/home-modes.md` with usage notes and the CNPG caveat.

## Surprises & Discoveries

- CloudNativePG `Cluster.spec.instances` cannot be set to `0`, so this mode system can only declaratively stop the selected Deployments and HelmRelease workloads, not the CNPG databases.

## Decision Log

- Decision: Switch modes by changing one cluster-level Kustomize resource path rather than editing many per-app manifests each time.
  Rationale: This keeps the operational toggle small, reviewable, and GitOps-native.
  Date/Author: 2026-04-27 / Codex

- Decision: Keep the existing base app manifests unchanged and introduce mode-specific wrapper directories under `apps/modes/`.
  Rationale: This minimizes churn in the base definitions and keeps mode behavior explicit.
  Date/Author: 2026-04-27 / Codex

- Decision: Leave CNPG database clusters out of the mode switch.
  Rationale: CNPG does not support `instances: 0`, and forcing DB shutdown declaratively would require a riskier design than this repo needs right now.
  Date/Author: 2026-04-27 / Codex

## Outcomes & Retrospective

The cluster now has a GitOps mode switch. The active mode is selected by a single line in `clusters/home/kustomization.yaml`, which now points at `modes/minecraft` by default. Both mode overlays build cleanly with Kustomize, and the helper script can switch between `apps` and `minecraft` modes by editing that one file.

The design intentionally stops at Deployment and HelmRelease scaling. CNPG-backed databases remain out of scope for mode switching because they cannot be scaled to zero declaratively with `spec.instances`.

## Context and Orientation

The root Flux sync points at `./clusters/home`. Today `clusters/home/kustomization.yaml` includes `flux-system` and `overlays`. The `overlays` tree contains Flux `Kustomization` objects for each app. Those Flux objects point at `./apps/<name>`.

The cleanest mode switch is to keep those base app directories intact, create mode-specific app wrappers in `apps/modes/`, and patch the Flux app Kustomization `spec.path` values from a mode overlay. Then the active mode is selected by a single resource entry in `clusters/home/kustomization.yaml`.

## Plan of Work

1. Add `apps/modes/apps/minecraft` to force Minecraft `replicaCount` to `0` in apps mode.
2. Add `apps/modes/minecraft/{hermes-agent,immich,paperless,kaneo}` to force those app Deployments to `0` in minecraft mode.
3. Add `clusters/home/modes/apps/kustomization.yaml` to include `../../overlays` and patch the Minecraft Flux Kustomization path.
4. Add `clusters/home/modes/minecraft/kustomization.yaml` to include `../../overlays` and patch the Hermes/Immich/Paperless/Kaneo Flux Kustomization paths.
5. Change `clusters/home/kustomization.yaml` to point at one active mode directory instead of `overlays` directly.
6. Add a helper script to swap the active mode path in `clusters/home/kustomization.yaml`.
7. Validate with `kustomize build` for both mode overlays and the active root path.

## Validation and Acceptance

The change is complete when:
- `kustomize build clusters/home/modes/apps --load-restrictor=LoadRestrictionsNone` succeeds
- `kustomize build clusters/home/modes/minecraft --load-restrictor=LoadRestrictionsNone` succeeds
- `kustomize build clusters/home --load-restrictor=LoadRestrictionsNone` succeeds
- The active mode path in `clusters/home/kustomization.yaml` clearly selects one mode
- The helper script updates only the active mode reference and validates cleanly with `bash -n`

## Idempotence and Recovery

This design is declarative and safe to reapply. Switching modes is done by a single Git change. To recover from a bad switch, change the active mode path back to the previous value and let Flux reconcile.

## Interfaces and Dependencies

- Root Flux sync: `clusters/home/flux-system/gotk-sync.yaml`
- Cluster root kustomization: `clusters/home/kustomization.yaml`
- Existing Flux app Kustomizations: `clusters/home/overlays/apps/*.yaml`
- Base app manifests: `apps/{minecraft,hermes-agent,immich,paperless,kaneo}`
