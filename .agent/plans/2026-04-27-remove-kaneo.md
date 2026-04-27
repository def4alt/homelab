# Remove Kaneo From Homelab Implementation Plan

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

Remove Kaneo from the Flux-managed homelab stack so it no longer deploys, no longer appears in active dashboards/monitoring, and no longer participates in the home cluster mode switch.

## Progress

- [x] (2026-04-27 00:00Z) Inspected the current Kaneo app, namespace, Flux overlay, and mode-switch references.
- [x] Remove Kaneo manifests, namespace, Flux overlay, and mode-switch references from the repo.
- [x] Remove Kaneo mentions from active docs and dashboards.
- [x] Validate the remaining Flux/Kustomize tree.
- [ ] Commit and push the removal.
- [ ] Reconcile Flux and confirm Kaneo resources are pruned.

## Surprises & Discoveries

- None yet.

## Decision Log

- Decision: Remove Kaneo declaratively through Git so Flux prunes the live resources.
  Rationale: Keeps the stack consistent and avoids manual cleanup drift.
  Date/Author: 2026-04-27 / Codex

## Outcomes & Retrospective

- Pending implementation.

## Context and Orientation

Kaneo previously existed as a full app subtree under `apps/kaneo`, with a dedicated namespace, Flux overlay, monitoring target, and Glance dashboard link. The home mode switch also previously referenced Kaneo in the minecraft-mode overlay and documentation.

The goal is to remove the app entirely without disturbing unrelated workloads.

## Plan of Work

1. Delete `apps/kaneo` and `apps/namespaces/namespace-kaneo.yaml`.
2. Remove `clusters/home/overlays/apps/kaneo.yaml` and the Kaneo entry from `clusters/home/overlays/kustomization.yaml`.
3. Remove the Kaneo patch from `clusters/home/modes/minecraft/kustomization.yaml` and delete `apps/modes/minecraft/kaneo`.
4. Remove active documentation and dashboard references from `README.md`, `docs/operations/home-modes.md`, `apps/glance/configmap.yaml`, and `apps/monitoring/blackbox-exporter-helmrelease.yaml`.
5. Update `apps/namespaces/kustomization.yaml` to drop the namespace manifest.
6. Validate with `kustomize build` for the active home tree.
7. Commit, push, and reconcile Flux.

## Validation and Acceptance

The removal is complete when:
- Kaneo manifests no longer exist in the repo
- Kaneo no longer appears in `clusters/home/overlays/kustomization.yaml` or the home mode overlay
- The active home kustomization builds cleanly
- Flux prunes Kaneo from the cluster after reconciliation

## Idempotence and Recovery

The deletion is safe to reapply because Flux will simply reconcile the absence of the resources. To restore Kaneo later, reintroduce the app subtree, namespace, overlay, and references from git history.

## Interfaces and Dependencies

- `apps/kaneo/*`
- `apps/namespaces/namespace-kaneo.yaml`
- `clusters/home/overlays/apps/kaneo.yaml`
- `clusters/home/modes/minecraft/kustomization.yaml`
- `README.md`
- `docs/operations/home-modes.md`
- `apps/glance/configmap.yaml`
- `apps/monitoring/blackbox-exporter-helmrelease.yaml`
