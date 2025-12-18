# Deploy Authentik SSO for all homelab access (LAN + Tailscale + Cloudflared) and remove Cloudflare Access

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository contains ExecPlan requirements at `.agent/PLANS.md`. This document must be maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

The goal is to make a single login experience (single-sign-on, “SSO”) apply everywhere you access the homelab: from the LAN, from Tailscale, and via public hostnames served through Cloudflare Tunnel (`cloudflared`). After this change, protected hostnames (for example `https://boards.def4alt.com`) always redirect to an Authentik login page unless the user has an active session, regardless of whether the request comes from public Internet, your home network, or Tailscale.

This plan intentionally removes Cloudflare Access as the authentication layer. Cloudflare Tunnel remains as the transport for public hostnames; authentication happens at the Kubernetes ingress layer (Traefik) using Authentik.

User-visible behavior at the end:

1. Browsing to any protected app hostname shows the Authentik login page first.
2. After login, the app loads normally.
3. The same hostname works internally and externally (split DNS), and the same login applies.
4. Cloudflare Access policies are not required for security.

## Progress

- [x] (2025-12-18) Add an `authentik` namespace and Flux wiring for the Authentik HelmRelease.
- [x] (2025-12-18) Provision Postgres for Authentik via CloudNativePG and store secrets with SOPS.
- [ ] (2025-12-18) Deploy Authentik and confirm the web UI is reachable on an internal hostname (completed: manifests; remaining: Flux reconcile + browser check).
- [ ] (2025-12-18) Integrate Traefik with Authentik via forward-auth middleware and protect one pilot app (completed: middleware resource; remaining: Authentik outpost/provider + app wiring).
- [ ] (2025-12-18) Roll out protection to all exposed app hostnames and validate websockets/uploads.
- [ ] (2025-12-18) Remove Cloudflare Access applications/policies and confirm public access is still protected.
- [ ] (2025-12-18) Document the “add a new protected app” workflow and the break-glass procedure.

## Surprises & Discoveries

- Observation: this repo’s `cloudflared` is in token mode, so tunnel routing is managed in Cloudflare Zero Trust.
  Evidence: `apps/cloudflared/deployment.yaml` runs `cloudflared tunnel run --token ...`.
- Observation: the upstream Authentik chart always references a config Secret named after the Helm release; we disable chart-managed secret creation and provide a SOPS-encrypted Secret named `authentik` instead.
  Evidence: Authentik server/worker templates use `envFrom.secretRef.name: {{ template "authentik.fullname" . }}` unconditionally.
- Observation: the Authentik automated-install bootstrap blueprint creates the default admin user as `akadmin` (not the value of `AUTHENTIK_BOOTSTRAP_USERNAME`), so logging in as `admin` will fail even if `AUTHENTIK_BOOTSTRAP_USERNAME=admin` is set.
  Evidence: `/blueprints/system/bootstrap.yaml` sets `context.username: akadmin`, and the server logs showed `invalid_identifier` for `admin` during login attempts.

## Decision Log

- Decision: use Authentik as the central identity provider and enforce auth at Traefik (Kubernetes ingress), not at Cloudflare Access.
  Rationale: the user requirement is SSO everywhere (LAN + Tailscale + public). Cloudflare Access only applies when traffic goes through Cloudflare, so it cannot be the single solution for internal paths without forcing internal traffic through Cloudflare.
  Date/Author: 2025-12-18 / Codex

- Decision: protect “non-OIDC apps” using Traefik forward-auth to an Authentik outpost, and configure “OIDC-capable apps” to use Authentik OIDC directly when feasible.
  Rationale: forward-auth provides coverage for everything; native OIDC gives better per-app identity/roles and fewer proxy edge cases.
  Date/Author: 2025-12-18 / Codex

## Outcomes & Retrospective

- (Not started) Expected outcome is consistent SSO across all access paths with fewer edge dependencies and a clear operational workflow.

## Context and Orientation

This repo deploys a k3s cluster via FluxCD with app manifests under `apps/` and cluster-level `Kustomization` ordering under `clusters/home/overlays/`.

Relevant existing components:

- Traefik ingress controller: `apps/traefik/helmrelease.yaml`
- Cloudflare Tunnel connector: `apps/cloudflared/deployment.yaml`
- CloudNativePG operator (Postgres): `apps/cnpg/`
- cert-manager: `apps/cert-manager/` and issuers in `apps/cert-manager-issuers/`

Key concept definitions:

- “Authentik”: a self-hosted identity provider (IdP) that can authenticate users via password, OAuth, OIDC, SAML, etc. In this plan, Authentik is the source of truth for who is allowed into your homelab.
- “OIDC” (OpenID Connect): an identity layer on top of OAuth 2.0 that issues ID tokens used for login. Many apps support it as “Login with SSO”.
- “Forward-auth”: a reverse-proxy pattern where Traefik asks an auth service “is this request allowed?” and only forwards to the app if the auth service approves.
- “Outpost”: Authentik’s component that integrates with reverse proxies. We use it to implement forward-auth for Traefik.
- “Split DNS”: internal DNS resolves the same public name (e.g. `boards.def4alt.com`) to an internal IP so LAN/Tailscale traffic goes directly to Traefik, while public DNS still points to Cloudflare.

## Plan of Work

### Milestone 1: Deploy Authentik and its database

At the end of this milestone, Authentik is running in-cluster with a persistent Postgres backend, and you can reach the Authentik UI on an internal hostname protected by TLS.

Implementation outline:

1. Create a new namespace `authentik` by adding `apps/namespaces/namespace-authentik.yaml` and including it in `apps/namespaces/kustomization.yaml`.
2. Add `apps/authentik/`:

   - `apps/authentik/helmrepository.yaml` pointing to the official Authentik chart repository.
   - `apps/authentik/helmrelease.yaml` installing Authentik with:
     - external Postgres connection info (CNPG cluster service DNS)
     - a Kubernetes secret for `AUTHENTIK_SECRET_KEY` and admin bootstrap credentials
     - an Ingress for `auth.<base_domain>` (or `authentik.<base_domain>`) on Traefik `websecure` with cert-manager TLS.

3. Create a CNPG Postgres cluster (1 instance to start) in `apps/authentik/postgres.yaml` and SOPS-encrypted init secrets in `apps/authentik/secrets/`.

Flux wiring:

4. Add a new overlay entry `clusters/home/overlays/infra/authentik.yaml` that reconciles `apps/authentik/` after `infra/cnpg.yaml` and after `infra/traefik.yaml` (since Authentik needs Postgres and ingress).

Acceptance:

- After Flux reconciles, browsing `https://auth.<base_domain>` loads the Authentik setup/login page.
- Postgres cluster is healthy and Authentik pods are ready.

### Milestone 2: Configure Traefik forward-auth via Authentik outpost

At the end of this milestone, Traefik can protect an app route by redirecting unauthenticated requests to Authentik.

Implementation outline:

1. In Authentik UI:

   - Create a “Proxy Provider” for Traefik forward-auth.
   - Deploy an “Embedded Outpost” (or Kubernetes outpost) and record the outpost service URL inside the cluster.

2. In Kubernetes manifests:

   - Create a Traefik Middleware resource `ForwardAuth` that calls the outpost endpoint.
   - Configure trust headers correctly (Auth headers come from Authentik; only Traefik should be allowed to set them).

3. Pilot: apply the middleware to a single Ingress (for example `apps/kan/ingress.yaml`) either via annotations (Ingress) or by moving to an IngressRoute + middleware reference.

Acceptance:

- `curl -I https://boards.<base_domain>` returns a 302 redirect to Authentik (not to Cloudflare Access).
- After login, you are redirected back and the app works.

### Milestone 3: Roll out across apps + handle app-specific protocols

At the end of this milestone, all relevant apps are protected the same way for LAN, Tailscale, and public traffic.

1. Add the forward-auth middleware to each app hostname:

   - `boards.<base_domain>` (Kan)
   - `papers.<base_domain>` (Paperless)
   - `photos.<base_domain>` (Immich)
   - `pihole.<base_domain>` (Pi-hole UI)
   - `home.<base_domain>` (Home Assistant)

2. Validate special cases:

   - Home Assistant websockets
   - large uploads (Immich / Nextcloud if present)

If any service breaks behind forward-auth, prefer configuring native OIDC for that app (Authentik as the IdP) instead of weakening proxy security.

### Milestone 4: Remove Cloudflare Access and ensure tunnel transport remains

At the end of this milestone, Cloudflare Access is not enforcing auth; Authentik + Traefik is.

1. In Cloudflare Zero Trust:

   - Remove/disable Access applications and policies that protect the homelab hostnames.
   - Keep tunnel public hostnames/routes intact (Cloudflare Tunnel still forwards to Traefik).

2. Validate from a network outside your LAN:

   - Accessing a protected hostname still redirects to Authentik.
   - You cannot access the origin without being authenticated.

### Milestone 5: Operational workflow + break-glass

At the end of this milestone, it is easy and safe to add a new protected app.

Document in-repo:

1. “Add a new app hostname” steps:

   - Create app Ingress with correct hostname + TLS
   - Add the Traefik forward-auth middleware reference
   - Add tunnel hostname in Cloudflare (token-mode) if it’s public
   - Add split DNS record internally

2. Break-glass:

   - Temporarily remove the middleware from the app Ingress (restores access internally).
   - If you must shut off public exposure quickly: remove the Cloudflare tunnel public hostname route (makes it unreachable from the Internet).

## Concrete Steps

Repository commands (run from repo root) to orient yourself:

1. List current app hostnames:

     rg -n "host:" apps

2. Inspect a pilot Ingress that will get auth first:

     sed -n '1,120p' apps/kan/ingress.yaml

Cluster validation commands (run on a machine with cluster access, not from this sandbox):

     kubectl -n authentik get pods
     kubectl -n authentik get ingress
     kubectl -n kan get ingress kan -o yaml

## Validation and Acceptance

Acceptance criteria:

1. Public, LAN, and Tailscale access to the same hostname results in the same Authentik login flow.
2. Removing Cloudflare Access policies does not reduce security; services remain protected.
3. No app requires a “bypass path” exception to function; if an app needs special treatment, it is switched to native OIDC.

## Idempotence and Recovery

- Kubernetes changes are GitOps-managed and can be rolled back by reverting commits and reconciling Flux.
- If Authentik is misconfigured and blocks access, remove the Traefik middleware reference from the affected Ingress (break-glass).
- If a tunnel route accidentally exposes a service you didn’t intend, remove the Cloudflare public hostname route to immediately cut off public traffic.

## Artifacts and Notes

Capture these as you implement:

- `curl -I` output showing redirect to Authentik for one hostname.
- Notes on any apps that required native OIDC.
- Authentik provider/outpost settings used for Traefik forward-auth.

## Interfaces and Dependencies

- Authentik Helm chart repository (installed via Flux HelmRelease).
- CloudNativePG for Postgres persistence.
- Traefik Middleware `ForwardAuth` resources and app Ingress wiring.
- Cloudflare Tunnel remains for public transport, but Cloudflare Access is removed.
