# Add Plex with Read-Only Access to the Transmission PVC

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the home cluster has a GitOps-managed Plex deployment that can scan and serve media directly from the existing Transmission downloads volume without taking ownership of that data path. Plex keeps its own config and metadata on a separate local PVC, while the Transmission PVC stays mounted read-only in the Plex container.

## Progress

- [x] (2026-06-09) Inspect the repo layout and confirm there is no existing Plex app pattern to extend.
- [x] (2026-06-09) Confirm the Transmission downloads live on `transmission-data-local` in the `transmission` namespace.
- [x] (2026-06-09) Add Plex manifests, local storage, and Flux overlay wiring.
- [x] (2026-06-09) Validate the new manifests with Kustomize and record follow-up risks.

## Surprises & Discoveries

- Kubernetes PVCs are namespace-scoped, so a Plex pod in a separate namespace cannot directly mount `transmission-data-local`.
- The existing Transmission workload already uses the `transmission` namespace, a `manual-local` PVC, and a hostPath-backed PV under `apps/local-storage/`.
- The `transmission` Flux Kustomization is currently suspended in repo state, but the namespace and PVC ownership pattern remain valid for a second app.

## Decision Log

- Decision: Run Plex in the `transmission` namespace instead of creating a separate `plex` namespace.
  Rationale: This keeps the shared PVC mount simple and avoids inventing a second hostPath/PV view of the same media path.
  Date/Author: 2026-06-09 / Codex

- Decision: Mount the Transmission PVC into Plex as read-only.
  Rationale: Plex only needs library access; Transmission should remain the only writer for that data path.
  Date/Author: 2026-06-09 / Codex

- Decision: Keep Plex’s config on its own local PVC.
  Rationale: Plex metadata grows independently from downloaded media and should not share lifecycle with the Transmission app state.
  Date/Author: 2026-06-09 / Codex

- Decision: Keep Plex internal-only for now with a `ClusterIP` service and no ingress.
  Rationale: The user asked for storage access, not a public hostname, and Plex exposure can be added separately once the library path is verified.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

The repo now contains a minimal Plex app under `apps/plex`, a dedicated local PV for Plex config, and a Flux overlay entry under `clusters/home/overlays/apps/plex.yaml`. Local validation succeeded for `apps/plex`, `apps/local-storage`, and `clusters/home/overlays`.

The remaining operational unknown is runtime behavior after Flux applies the change. Plex should be able to read `/media/transmission` from the shared claim, but I have not yet verified the running pod, library scan behavior, or any first-run Plex claim/login flow.

## Context and Orientation

This repository uses Flux `Kustomization` objects under `clusters/home/overlays/` that point to app directories under `apps/`. Local-disk persistence uses `manual-local` PVCs backed by explicit hostPath PVs stored in `apps/local-storage/`.

Transmission currently owns a PVC named `transmission-data-local` in the `transmission` namespace. Its `downloads` subPath is the useful media path for Plex. A Plex deployment can mount that same claim read-only if it runs in the same namespace, while a second PVC stores Plex config.

## Plan of Work

Create a new `apps/plex` directory with a `Deployment`, `Service`, `PersistentVolumeClaim`, and `kustomization.yaml`. The deployment should run Plex in the `transmission` namespace, mount a dedicated config PVC at `/config`, and mount the existing `transmission-data-local` claim at a read-only media path.

Add a new hostPath-backed PV under `apps/local-storage/` for the Plex config volume, then wire the app into `clusters/home/overlays/apps/` with dependencies on `namespaces` and `local-storage`.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1. Add the app manifests:
   - `apps/plex/kustomization.yaml`
   - `apps/plex/deployment.yaml`
   - `apps/plex/service.yaml`
   - `apps/plex/pvc.yaml`

2. Add local storage:
   - `apps/local-storage/pv-plex-config.yaml`
   - Update `apps/local-storage/kustomization.yaml`

3. Wire Flux for the home cluster:
   - `clusters/home/overlays/apps/plex.yaml`
   - Update `clusters/home/overlays/kustomization.yaml`

4. Validate:
   - Run `kubectl kustomize apps/plex`
   - Run `kubectl kustomize apps/local-storage`
   - Run `kubectl kustomize clusters/home/overlays`

## Validation and Acceptance

After Flux reconciles the change, the expected outcomes are:

- Plex runs in the `transmission` namespace.
- The Plex config PVC binds successfully.
- Plex mounts the Transmission data claim read-only and a separate config PVC read-write.
- The service exposes Plex on port `32400` inside the cluster.

## Idempotence and Recovery

This change is safe to re-apply through Flux. If Plex config storage needs to grow, increase the PVC request and PV capacity together.

If Plex should later live behind an ingress or a different hostname, that can be added without changing the shared media-mount approach.

## Interfaces and Dependencies

- Flux app overlays live in `clusters/home/overlays/apps/`.
- Local hostPath PVs live in `apps/local-storage/`.
- The Plex app will rely on the existing `transmission` namespace and PVC.

Change note: Initial ExecPlan created for a Plex deployment that reads the Transmission PVC read-only.
