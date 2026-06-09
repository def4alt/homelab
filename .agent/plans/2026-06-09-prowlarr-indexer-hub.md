# Add Prowlarr as the Shared Indexer Hub

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the home cluster has a GitOps-managed Prowlarr deployment that acts as the shared indexer manager for Sonarr and Radarr. Instead of configuring indexers separately in each Arr app, Prowlarr becomes the single place to add and maintain them, while Sonarr and Radarr stay focused on search, import, and download workflow.

## Progress

- [x] (2026-06-09) Inspect the current Sonarr/Radarr layout and confirm the existing Arr stack is running in the `transmission` namespace.
- [x] (2026-06-09) Add Prowlarr manifests, local config storage, and Flux overlay wiring.
- [x] (2026-06-09) Add a private tailnet-style hostname for Prowlarr.
- [x] (2026-06-09) Reconcile the live cluster and connect Prowlarr to Sonarr and Radarr.

## Surprises & Discoveries

- Sonarr and Radarr are already live with app API keys generated in their persisted config volumes, so Prowlarr can be linked to them after deployment without adding new secrets to Git.
- The private hostname pattern already exists for `tv.def4alt.com`, `sonarr.def4alt.com`, and `radarr.def4alt.com`, so Prowlarr should follow the same tailnet-backed CNAME approach.
- Prowlarr's application API wants Arr-side `baseUrl` values that are resolvable from inside the cluster, so the correct links are `http://sonarr:8989` and `http://radarr:7878` rather than the external hostnames.

## Decision Log

- Decision: Run Prowlarr in the `transmission` namespace.
  Rationale: Keeping the Arr stack together simplifies service discovery and follows the current media-automation pattern in this repo.
  Date/Author: 2026-06-09 / Codex

- Decision: Give Prowlarr its own local config PVC and no shared media mount.
  Rationale: Prowlarr manages indexers and Arr application links; it does not need direct access to the shared downloads/media filesystem.
  Date/Author: 2026-06-09 / Codex

- Decision: Expose Prowlarr at `prowlarr.def4alt.com` over the same private tailnet-backed path as Sonarr and Radarr.
  Rationale: This keeps the whole Arr control plane private-only and avoids reintroducing Cloudflare proxying into the workflow.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

The repo now includes a new `apps/prowlarr` app directory, `apps/local-storage/pv-prowlarr-config.yaml`, `clusters/home/overlays/apps/prowlarr.yaml`, and a `prowlarr.${var.base_domain}` private tailnet-style DNS entry in `cloudflare/locals.tf`. The rollout is live in the `transmission` namespace with a bound config PVC, a ready TLS certificate, and a working private hostname at `https://prowlarr.def4alt.com`.

Runtime wiring is also complete: Prowlarr has live application links to Sonarr and Radarr, using cluster-local URLs and the existing Arr API keys stored in their config volumes. Indexers still need to be added in Prowlarr before automatic search or RSS sync can work across the stack.

## Context and Orientation

This repository uses Flux `Kustomization` objects under `clusters/home/overlays/` that point to app directories under `apps/`. Local state uses `manual-local` PVCs backed by explicit hostPath PVs under `apps/local-storage/`.

Sonarr and Radarr already run in the `transmission` namespace with private hostnames and working Transmission integrations. Prowlarr only needs cluster-local access to those services and its own persistent config storage.

## Plan of Work

Create a new `apps/prowlarr` directory with a `Deployment`, `Service`, `Ingress`, `PersistentVolumeClaim`, and `kustomization.yaml`. The deployment should run Prowlarr in the `transmission` namespace with its own config PVC mounted at `/config`.

Add a hostPath-backed PV under `apps/local-storage/`, wire the app into `clusters/home/overlays/apps/`, add the hostname to `cloudflare/locals.tf`, validate the manifests, reconcile Flux, apply OpenTofu, and then connect Prowlarr to Sonarr and Radarr through the live APIs.

## Concrete Steps

1. Add app manifests:
   - `apps/prowlarr/kustomization.yaml`
   - `apps/prowlarr/deployment.yaml`
   - `apps/prowlarr/service.yaml`
   - `apps/prowlarr/ingress.yaml`
   - `apps/prowlarr/pvc.yaml`

2. Add local storage:
   - `apps/local-storage/pv-prowlarr-config.yaml`
   - update `apps/local-storage/kustomization.yaml`

3. Wire Flux and DNS:
   - `clusters/home/overlays/apps/prowlarr.yaml`
   - update `clusters/home/overlays/kustomization.yaml`
   - update `cloudflare/locals.tf`

4. Validate and apply:
   - `kubectl kustomize apps/prowlarr`
   - `kubectl kustomize apps/local-storage`
   - `kubectl kustomize clusters/home/overlays`
   - reconcile Flux
   - `tofu apply`

5. Runtime wiring:
   - connect Prowlarr to Sonarr
   - connect Prowlarr to Radarr

## Validation and Acceptance

After Flux reconciles the change, the expected outcomes are:

- Prowlarr runs in the `transmission` namespace.
- The Prowlarr config PVC is bound.
- `prowlarr.def4alt.com` resolves through the private tailnet path.
- Prowlarr can reach Sonarr and Radarr through cluster-local services.
- Sonarr and Radarr can be managed from Prowlarr once indexers are added there.

## Idempotence and Recovery

The manifests are safe to re-apply through Flux. Runtime application links inside Prowlarr live in its config volume, so re-running those API calls should be treated carefully to avoid duplicate app registrations.

## Interfaces and Dependencies

- Flux app overlays live in `clusters/home/overlays/apps/`.
- Local hostPath PVs live in `apps/local-storage/`.
- Prowlarr depends on the existing `transmission` namespace and local storage.
