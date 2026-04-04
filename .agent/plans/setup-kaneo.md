# Add Kaneo to the Homelab GitOps Stack

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, Kaneo is deployed through Flux in its own namespace and is reachable at `https://projects.def4alt.com` with Traefik, cert-manager TLS, and Authentik forward-auth protection. The app uses a dedicated PostgreSQL database managed in Kubernetes, and the repo includes the corresponding DNS, dashboard, and README references so the service is discoverable and fully GitOps-managed.

## Progress

- [x] (2026-04-04) Create the Kaneo app manifests, namespace, and Flux overlay wiring.
- [x] (2026-04-04) Add the Kaneo hostname to Cloudflare, Glance, and the repo README references.
- [x] (2026-04-04) Validate the manifests locally with kustomize and record any follow-up fixes.
- [x] (2026-04-04) Adjust Kaneo web startup probes after discovering the nginx container needs more startup time in-cluster.

## Surprises & Discoveries

- Kaneo’s upstream docs and chart confirm the app expects `DATABASE_URL`, `AUTH_SECRET`/`BETTER_AUTH_SECRET`, `KANEO_API_URL`, `KANEO_CLIENT_URL`, and `CORS_ORIGINS`.
- The upstream deployment pattern is a combined API + Web pod, but the app can be deployed with separate containers in one Deployment and a single Service exposing both ports.
- The web image is an nginx container that listens on port 5173, but kubelet probes need enough startup grace or the pod never becomes Ready and Traefik returns 503.

## Decision Log

- Decision: Use a dedicated namespace `kaneo` and keep the deployment Flux-first under `apps/kaneo`.
  Rationale: This matches the existing homelab app layout and keeps the new service isolated.
  Date/Author: 2026-04-04 / Codex

- Decision: Use a single SOPS-managed application secret containing both database credentials and the database URL.
  Rationale: This keeps the app configuration compact while still following the repo’s encrypted-secret pattern.
  Date/Author: 2026-04-04 / Codex

- Decision: Expose Kaneo on the root host `projects.def4alt.com` with path-based routing for `/` and `/api`.
  Rationale: That matches Kaneo’s documented setup and avoids introducing an extra public hostname.
  Date/Author: 2026-04-04 / Codex

## Outcomes & Retrospective

Pending.

## Context and Orientation

The repository uses Flux overlays under `clusters/home/overlays/` to point at app directories in `apps/`. Namespaces are managed separately through `apps/namespaces`, and the root `clusters/home/overlays/kustomization.yaml` must include both the namespace overlay and the app overlay for a new service.

Kaneo’s upstream repository documents a Docker Compose setup with `ghcr.io/usekaneo/api:latest`, `ghcr.io/usekaneo/web:latest`, and PostgreSQL 16. The Helm chart docs show that the API listens on port `1337`, the web frontend listens on `5173`, the API health endpoint is `/api/health`, and the frontend should use the same public host as the API base URL. For this homelab, the app should be protected with the existing `infra-authentik-forward-auth` middleware and served with cert-manager TLS like the other public apps.

## Plan of Work

Create a new `apps/kaneo` directory with a Kubernetes `Deployment` that runs the Kaneo API and web containers together, a `Service` exposing both ports, and a Traefik `Ingress` for `projects.def4alt.com` that routes `/` to the web service port and `/api` to the API service port. Add a dedicated PostgreSQL `Cluster` for Kaneo plus the standard CNPG backup resources used by the other database-backed apps, and store the DB credentials plus the Kaneo auth secret in one SOPS-managed secret.

Wire the new namespace into `apps/namespaces`, add the Flux overlay under `clusters/home/overlays/apps`, and include the new overlay in `clusters/home/overlays/kustomization.yaml`. Update `cloudflare/locals.tf` so DNS management includes `projects.def4alt.com`. Add a Kaneo link to the Glance dashboard, and update `README.md` so the new app and its secret are documented alongside the rest of the stack.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1) Create the Kaneo app manifests:
   - `apps/kaneo/kustomization.yaml`
   - `apps/kaneo/deployment.yaml`
   - `apps/kaneo/service.yaml`
   - `apps/kaneo/ingress.yaml`
   - `apps/kaneo/postgres-cluster.yaml`
   - `apps/kaneo/barman-objectstore.yaml`
   - `apps/kaneo/scheduled-backup.yaml`
   - `apps/kaneo/secrets/kaneo-secrets.sops.yaml`

2) Add namespace and Flux wiring:
   - `apps/namespaces/namespace-kaneo.yaml`
   - Add the namespace file to `apps/namespaces/kustomization.yaml`
   - `clusters/home/overlays/apps/kaneo.yaml`
   - Add the app overlay to `clusters/home/overlays/kustomization.yaml`

3) Update cross-references:
   - `cloudflare/locals.tf`
   - `apps/glance/configmap.yaml`
   - `README.md`

4) Sanity-check the manifests:
   - Run `kustomize build apps/kaneo` and expect valid YAML for the Deployment, Service, Ingress, CNPG Cluster, backup resources, and secret.
   - Run `kustomize build clusters/home/overlays` and expect no missing-resource or kustomization errors.

## Validation and Acceptance

After Flux reconciles the change, the expected outcomes are:

- `https://projects.def4alt.com` serves the Kaneo UI.
- `/api/health` responds successfully through the ingress path.
- Authentik forward-auth still protects the public endpoint.
- The Kaneo namespace exists and the database cluster becomes ready.
- Glance includes a Kaneo link.
- Cloudflare DNS management includes `projects.def4alt.com`.

## Idempotence and Recovery

This change is safe to re-apply through Flux. If the app needs extra environment variables later, they should be added to the same SOPS-managed secret or a small companion ConfigMap rather than creating new bootstrap resources.

If the database bootstrap needs to be adjusted, update the CNPG cluster and secret together so the app and database credentials stay in sync.

## Artifacts and Notes

- Upstream Kaneo repository: `https://github.com/usekaneo/kaneo`
- Upstream docs landing page: `https://kaneo.app/docs`
- Compose reference provided by the user uses:
  - `ghcr.io/usekaneo/api:latest`
  - `ghcr.io/usekaneo/web:latest`
  - `postgres:16-alpine`

## Interfaces and Dependencies

- Flux Kustomizations live under `clusters/home/overlays/`.
- Namespace manifests live under `apps/namespaces/`.
- Traefik ingress annotations should match the other protected apps in this repo.
- cert-manager uses the `letsencrypt-prod` cluster issuer.
- Kaneo’s database should be reachable via a Postgres connection string stored in the app secret.

Change note: Initial ExecPlan created for Kaneo deployment, DNS, dashboard, and README integration.
