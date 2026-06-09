# Add Sonarr and Radarr for Jellyfin Media Automation

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the home cluster has GitOps-managed Sonarr and Radarr services that can hand downloads to Transmission and then import completed content into clean library folders on the existing shared media PVC. Jellyfin keeps reading from that same PVC, but it can shift from scanning raw download folders to scanning managed `tv` and `movies` library paths instead.

## Progress

- [x] (2026-06-09) Inspect the existing Transmission and Jellyfin layouts and confirm there is no existing Arr pattern to extend.
- [x] (2026-06-09) Add Sonarr and Radarr manifests, local config storage, and Flux overlay wiring.
- [x] (2026-06-09) Confirm Jellyfin already mounts the shared PVC in a way that can see managed library paths without a deployment change.
- [x] (2026-06-09) Validate all manifests and record runtime follow-up work.

## Surprises & Discoveries

- Transmission currently mounts the shared PVC as three subpaths: `/config`, `/downloads`, and `/watch`.
- Jellyfin already mounts the entire shared PVC read-only, so it can see both current download folders and any future managed library folders on the same claim.
- The repo already uses local hostPath-backed PVs for app config state, so Sonarr and Radarr should follow that same pattern for `/config`.
- The current shared PVC layout already allows a clean convention: Arr apps can use `/data/downloads` as the download root and `/data/media/{tv,movies}` as curated library roots, while Transmission continues to use `/downloads` inside its own container.
- Sonarr and Radarr both rely on Transmission category subdirectories, so the shared PVC layout must include `/data/downloads/complete/tv-sonarr` and `/data/downloads/complete/movies-radarr` up front or Arr validation reports missing remote paths before the first categorized download lands.

## Decision Log

- Decision: Run Sonarr and Radarr in the `transmission` namespace.
  Rationale: They need direct access to the same shared PVC as Transmission, and co-locating them avoids cross-namespace PVC limitations.
  Date/Author: 2026-06-09 / Codex

- Decision: Give Sonarr and Radarr separate config PVCs, but mount the shared Transmission PVC read-write for library import paths.
  Rationale: App state should stay isolated, while media organization must operate on the same underlying files to allow moves or hardlinks without a second storage system.
  Date/Author: 2026-06-09 / Codex

- Decision: Use managed library folders on the existing shared PVC instead of introducing a second media PVC.
  Rationale: The current local-disk PVC is already the canonical media store, and keeping downloads plus curated libraries on the same filesystem keeps hardlink-friendly automation possible later.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

This plan starts before the manifests exist. The expected repo outcome is new `apps/sonarr` and `apps/radarr` directories, two local PV definitions for app config, Flux overlays under `clusters/home/overlays/apps/`, and a small Jellyfin deployment adjustment if needed to make the managed library paths obvious.

Implementation outcome on 2026-06-09: the repo now has `apps/sonarr` and `apps/radarr` with `Deployment`, `Service`, `Ingress`, `PVC`, and `kustomization.yaml` files, plus two new local PV definitions under `apps/local-storage/`. Each app mounts its own config PVC at `/config` and the shared media PVC at `/data`. Init containers create `/data/media/tv`, `/data/media/movies`, `/data/downloads/complete/{tv-sonarr,movies-radarr}`, and the expected download staging directories if they do not exist yet.

## Context and Orientation

This repository uses Flux `Kustomization` objects under `clusters/home/overlays/` that point to app directories under `apps/`. Local state uses `manual-local` PVCs backed by explicit hostPath PVs under `apps/local-storage/`.

Transmission currently owns the shared PVC `transmission-data-local` in the `transmission` namespace. That PVC already holds Transmission config and download data. Sonarr and Radarr should treat that claim as the shared media filesystem, while Jellyfin remains the read-only consumer.

Operational path convention for the apps:

- Transmission download path inside its container: `/downloads`
- Sonarr/Radarr view of the same files: `/data/downloads`
- Sonarr managed TV library target: `/data/media/tv`
- Radarr managed movie library target: `/data/media/movies`
- Jellyfin read-only view of the library roots: `/media/transmission/media/tv` and `/media/transmission/media/movies`
- Private Arr UI hostnames: `sonarr.def4alt.com` and `radarr.def4alt.com`

## Plan of Work

Create new `apps/sonarr` and `apps/radarr` directories with `Deployment`, `Service`, `PersistentVolumeClaim`, and `kustomization.yaml` files. Each deployment should run in the `transmission` namespace with its own config PVC mounted at `/config` and the shared Transmission PVC mounted at `/data` so the app can see download staging plus managed library directories.

Add hostPath-backed PVs under `apps/local-storage/` for Sonarr and Radarr config, wire both apps into `clusters/home/overlays/apps/`, and validate the rendered manifests. Keep ingress and public hostnames out of scope unless explicitly requested later.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1. Add app manifests:
   - `apps/sonarr/kustomization.yaml`
   - `apps/sonarr/deployment.yaml`
   - `apps/sonarr/service.yaml`
   - `apps/sonarr/pvc.yaml`
   - `apps/radarr/kustomization.yaml`
   - `apps/radarr/deployment.yaml`
   - `apps/radarr/service.yaml`
   - `apps/radarr/pvc.yaml`

2. Add local storage:
   - `apps/local-storage/pv-sonarr-config.yaml`
   - `apps/local-storage/pv-radarr-config.yaml`
   - update `apps/local-storage/kustomization.yaml`

3. Wire Flux:
   - `clusters/home/overlays/apps/sonarr.yaml`
   - `clusters/home/overlays/apps/radarr.yaml`
   - update `clusters/home/overlays/kustomization.yaml`

4. Validate:
   - `kubectl kustomize apps/sonarr`
   - `kubectl kustomize apps/radarr`
   - `kubectl kustomize apps/local-storage`
   - `kubectl kustomize clusters/home/overlays`

## Validation and Acceptance

After Flux reconciles the change, the expected outcomes are:

- Sonarr and Radarr run in the `transmission` namespace.
- Each app has its own bound config PVC.
- Each app mounts the shared Transmission PVC read-write at a consistent path.
- Jellyfin can be pointed at curated library folders on that same PVC.
- Sonarr and Radarr are reachable through private tailnet-backed hostnames.
- No change weakens the existing Transmission VPN confinement model.

Follow-up runtime work still needed after apply:

- Configure Sonarr and Radarr download client path mapping from Transmission `/downloads` to local `/data/downloads`.
- Point Jellyfin libraries at curated roots instead of raw download folders if you want a cleaner media catalog.

## Idempotence and Recovery

The manifests are safe to re-apply through Flux. If the library layout needs to evolve later, that should be handled inside app configuration or with a one-time migration, not by replacing the shared PVC.

## Interfaces and Dependencies

- Flux app overlays live in `clusters/home/overlays/apps/`.
- Local hostPath PVs live in `apps/local-storage/`.
- Sonarr and Radarr depend on the existing `transmission` namespace and shared PVC.
