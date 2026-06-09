# Add Plex Alongside Jellyfin with Read-Only Access to the Transmission PVC

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the home cluster has a second GitOps-managed media server alongside Jellyfin. Plex runs in the existing `transmission` namespace, reads the shared Transmission media claim read-only, keeps its own config on a dedicated local PVC, and is exposed through the same protected public UI pattern at `tv-plex.def4alt.com`.

## Progress

- [x] (2026-06-09) Inspect the existing Jellyfin and Transmission patterns to reuse the same namespace, storage class, and ingress model.
- [x] (2026-06-09) Add Plex app manifests, local storage, and Flux overlay wiring.
- [x] (2026-06-09) Validate the new manifests with Kustomize.
- [ ] (2026-06-09) Commit, push, and reconcile the change for the home cluster.
- [ ] (2026-06-09) Apply the Cloudflare hostname and tunnel route for `tv-plex.def4alt.com`.

## Surprises & Discoveries

- Reusing the `transmission` namespace is still the cleanest way to share the existing `transmission-data-local` PVC without inventing another hostPath view of the same data.
- The home cluster already uses a consistent protected UI pattern of `ClusterIP` service, Traefik TLS ingress, and Authentik forward-auth, so Plex should follow that instead of exposing its service directly.

## Decision Log

- Decision: Run Plex in the `transmission` namespace and mount `transmission-data-local` read-only.
  Rationale: Plex only needs library access and should not compete with Transmission for writes on the media volume.
  Date/Author: 2026-06-09 / Codex

- Decision: Give Plex its own local config PV/PVC.
  Rationale: Plex metadata, cache, and configuration should not share lifecycle with Jellyfin or Transmission state.
  Date/Author: 2026-06-09 / Codex

- Decision: Expose Plex at `tv-plex.def4alt.com` behind Traefik, cert-manager, Authentik forward-auth, and the existing Cloudflare tunnel path.
  Rationale: This keeps the public surface consistent with other protected home-cluster services.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

The repo now contains an `apps/plex` app, a dedicated local PV for Plex config, a Flux overlay entry under `clusters/home/overlays/apps/plex.yaml`, and the `tv-plex.def4alt.com` hostname in Cloudflare locals. Local validation succeeded for `apps/plex`, `apps/local-storage`, and `clusters/home/overlays`.

The remaining operational work is live rollout: commit and push the repo state, reconcile Flux so the cluster creates the deployment, and apply OpenTofu so Cloudflare serves the new hostname through the existing tunnel path.

## Context and Orientation

The repository uses Flux `Kustomization` objects under `clusters/home/overlays/` that point to app directories under `apps/`. Local persistent storage uses `manual-local` PVCs backed by explicit hostPath PVs in `apps/local-storage/`.

Transmission already owns the shared media claim `transmission-data-local` in the `transmission` namespace. Jellyfin demonstrates the current pattern for a second media app that mounts that claim read-only and keeps its own config on a separate local PVC.

## Plan of Work

Create a new `apps/plex` directory with a `Deployment`, `Service`, `Ingress`, `PersistentVolumeClaim`, and `kustomization.yaml`. The deployment should run Plex in the `transmission` namespace, mount its own config PVC at `/config`, provide a transient `/transcode` scratch volume, and mount the existing `transmission-data-local` claim read-only at `/media/transmission`.

Add a new hostPath-backed PV under `apps/local-storage/`, wire the app into `clusters/home/overlays/apps/`, add the hostname to `cloudflare/locals.tf`, and then validate, reconcile, and apply the Cloudflare change.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1. Add the app manifests:
   - `apps/plex/kustomization.yaml`
   - `apps/plex/deployment.yaml`
   - `apps/plex/service.yaml`
   - `apps/plex/ingress.yaml`
   - `apps/plex/pvc.yaml`

2. Add local storage:
   - `apps/local-storage/pv-plex-config.yaml`
   - Update `apps/local-storage/kustomization.yaml`

3. Wire Flux and DNS:
   - `clusters/home/overlays/apps/plex.yaml`
   - Update `clusters/home/overlays/kustomization.yaml`
   - Update `cloudflare/locals.tf`

4. Validate and roll out:
   - Run `kubectl kustomize apps/plex`
   - Run `kubectl kustomize apps/local-storage`
   - Run `kubectl kustomize clusters/home/overlays`
   - Commit and push
   - Reconcile Flux and apply OpenTofu in `cloudflare/`

## Validation and Acceptance

After reconciliation and Cloudflare apply, the expected outcomes are:

- Plex runs in the `transmission` namespace.
- The Plex config PVC binds successfully.
- Plex mounts the Transmission data claim read-only and cannot mutate the download path.
- The service exposes Plex on port `32400` inside the cluster.
- `tv-plex.def4alt.com` routes to the Plex ingress through the protected public path.

## Idempotence and Recovery

This change is safe to re-apply through Flux. The Plex config volume can be grown later by increasing the PV capacity and matching PVC request.

If Plex should later use a hardware transcode path or a different auth model, that can be added without changing the shared-media mount approach.

## Interfaces and Dependencies

- Flux app overlays live in `clusters/home/overlays/apps/`.
- Local hostPath PVs live in `apps/local-storage/`.
- Plex depends on the existing `transmission` namespace and `transmission-data-local` PVC.
