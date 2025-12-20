# ExecPlan: Glance Homelab Dashboard

## Goal

Deliver an always-on Glance dashboard that aggregates upstream status telemetry (e.g., Traefik, Longhorn, Pi-hole, Immich, Docmost, CNPG) via the k3s cluster and presents a unified overview for the homelab, while remaining declarative within Flux/CD and secured behind existing ingress/auth.

## Scope (this repo)

- Deploying and configuring new Kubernetes resources (`apps/glance` overlay + Flux `clusters/home/overlays` entry).
- Reusing existing infrastructure: Traefik ingress, authentik forward auth, Cloudflare tunnel, Longhorn storage, Backblaze S3 for persistence if needed.
- Integrating with existing secrets/credentials (SOPS-managed) and ensuring the dashboard respects current networking/auth patterns.
- Not covering offline/edge Glance connectors outside homelab (those can be added later).

## Design

### Architecture

- **Application** – Glance (https://glance.sh) as a Kubernetes Deployment with a PVC for persistent metrics data, served behind Traefik and `infra-authentik-forward-auth`.
- **Storage** – Longhorn PVC (1-2Gi) for Glance internal DB/backups; optionally back up via Restic (already job backs up entire `/var/lib/longhorn`).
- **Ingress** – Traefik Route using `dashboard.def4alt.com` with TLS via cert-manager. Reuse `Cloudflare` tunnel plus authentik forward auth.
- **Observability** – Glance connectors poll local services (CNPG metrics, Longhorn API, Pi-hole DNS stats, Immich server). Use Kubernetes ServiceAccounts + network policies if needed.
- **Flux integration** – Add `apps/glance` kustomization and wire into `clusters/home/overlays/infra` or new overlay. Document secret values in `apps/glance/secrets`.
- **Security** – Dash behind authentik; optionally limit access via Cloudflare Access. Use TLS cert and limit ingress to require auth.

## Implementation Steps

1. Create `apps/glance` directory with:
   - `kustomization.yaml` referencing Deployment, Service, PVC, Secret(s), ingress.
   - `deployment.yaml` using Glance Docker image, environment variables, readiness/liveness probes.
   - `service` + `pvc` definitions using Longhorn storage class.
  - `ingress` referencing `dashboard.def4alt.com` + authentik middleware + TLS secret.
   - `secrets/glance-config.sops.yaml` (if needed) holding API tokens etc.
2. Add `apps/glance/helmrepository.yaml` if using Helm chart; otherwise use plain manifests.
3. Add Flux overlay entry under `clusters/home/overlays` (e.g., `infra/glance.yaml`) to deploy `apps/glance` in namespace `glance`.
4. Configure Glance connectors:
   - CNPG: use Postgres/metrics endpoints via `ClusterRole` or service monitor.
   - Longhorn: point to Longhorn API (use service account token + TLS config).
   - Pi-hole/Immich/Docmost: use HTTP health endpoints or Prometheus metrics if exposed (via NodePort/Service).
   - Optionally configure watchers for restic/backup statuses.
5. Wire DNS/ingress:
   - Update Traefik middlewares (if necessary).
   - Ensure Cloudflare DNS + tunnel route exists for `dashboard.def4alt.com`.
6. Document access: update README or `apps/glance/README.md` describing how to log in (authentik), and how to add new connectors.
7. Add any necessary RBAC (ServiceAccount + RoleBinding) so Glance can query Kubernetes APIs or CNPG metrics; limit to least privilege.
8. Add a simple `CronJob` or ConfigMap that seeds connectors with initial queries (if Glance requires) and sets retention policy.

## Verification

- Flux-level:
  - `flux reconcile kustomization glance -n flux-system`.
  - Confirm `kubectl -n glance get deploy,svc,ingress`.

- Runtime:
  - Visit `https://dashboard.def4alt.com` and ensure authentik login works and dashboard loads.
  - Verify connectors report data for at least Traefik, Longhorn, Pi-hole, Immich/Docmost.
  - Check logs (`kubectl -n glance logs <pod>`) for errors and readiness.
  - Confirm the Glance PVC is backed by Longhorn and Restic already covers it.

- Monitoring:
  - Set up alerts if Glance pods crash (e.g., `kubectl -n glance get events`, watch for restarts).
  - Document how to add new connectors in repo docs so future services can be plated.

## Risks & Mitigations

- **Over-privileged access** – Keep Glance ServiceAccount limited; only expose necessary Kubernetes metrics via Read-only roles.
- **Ingress drift** – Ensure Traefik middleware changes go through Flux so the authentik forward auth state remains consistent; keep TLS cert referenced.
- **Storage growth** – Glance caches not huge, but monitor PVC size and add `EmptyDir` cleanups if needed.
- **Secret exposure** – Keep API keys in the SOPS secret and do not include them in CI logs.

## Progress Log

- 2026-01-03: ExecPlan created; awaiting stakeholder feedback on connectors and domain name.
  - 2026-01-04: Glance app manifests, Startpage config, Longhorn PVC, and Traefik ingress for `dashboard.def4alt.com` added; Flux overlay wiring launched.
- 2026-01-05: Added Immich API ingress so mobile clients can bypass forward-auth, plus Cloudflare DNS for `api-photos.def4alt.com`.
