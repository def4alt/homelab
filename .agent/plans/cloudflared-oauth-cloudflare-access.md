# Protect exposed homelab services with OAuth via Cloudflare Access (cloudflared tunnel)

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This repository contains ExecPlan requirements at `.agent/PLANS.md`. This document must be maintained in accordance with `.agent/PLANS.md`.

## Purpose / Big Picture

The goal is to put single-sign-on (SSO) in front of every homelab service that is exposed to the Internet through the existing Cloudflare Tunnel (`cloudflared`). After this change, visiting any protected hostname (for example `https://kan.def4alt.com`) first shows a Cloudflare Access login screen, then redirects back to the service after the user signs in with an OAuth provider (for example Google or GitHub). Unauthenticated users should not be able to reach the origin service at all.

The key user-visible behavior is: “public DNS resolves, but the service is not reachable without logging in”.

## Progress

- [x] (2025-12-18) Inventory candidate hostnames from Kubernetes Ingress resources (`kan`, `papers`, `photos`, `pihole`, `home`).
- [x] (2025-12-18) Add Terraform under `cloudflare/` to manage Cloudflare Access apps/policies for those hostnames, and validate the configuration locally.
- [ ] (2025-12-18) Apply for one pilot hostname (in Cloudflare) and validate browser + CLI.
- [ ] (2025-12-18) Enable tunnel route management (optional) and validate correct Host header + TLS SNI to Traefik.
- [ ] (2025-12-18) Roll out to remaining hostnames and validate websockets/large uploads where applicable.
- [ ] (2025-12-18) Add operational guardrails (service tokens for automation, documented break-glass bypass, and a quick rollback procedure).
- [ ] (2025-12-18) Document the final “how to add a new protected hostname” workflow in-repo.

## Surprises & Discoveries

- Observation: this repo deploys `cloudflared` in “token mode”, which means the tunnel ingress rules are managed in Cloudflare Zero Trust, not via a Kubernetes `config.yaml`.
  Evidence: `apps/cloudflared/deployment.yaml` runs `cloudflared tunnel run --token $(TUNNEL_TOKEN)`.
- Observation: in this Codex CLI environment, Terraform provider plugins may require escalated permissions because they create local Unix sockets during `terraform validate`.
  Evidence: `terraform validate` initially failed with `bind: operation not permitted` until rerun with escalated sandbox permissions.

## Decision Log

- Decision: use Cloudflare Access (edge enforcement) as the OAuth gate for all Internet-exposed services, rather than deploying an in-cluster forward-auth proxy (for example `oauth2-proxy`) in front of each app.
  Rationale: it fits the existing `cloudflared` token-mode setup, keeps auth logic out of the cluster, and protects services even if an app has no native authentication.
  Date/Author: 2025-12-18 / Codex

- Decision: route Cloudflare Tunnel public hostnames to the in-cluster Traefik service over HTTPS and set both the HTTP Host header and TLS SNI to the requested public hostname.
  Rationale: current Ingress resources are configured for Traefik’s `websecure` entrypoint with per-host TLS certificates (via cert-manager); routing over plain HTTP would bypass that and/or fail to match routes.
  Date/Author: 2025-12-18 / Codex

- Decision: codify Cloudflare Access configuration in Terraform under `cloudflare/`, with tunnel routing and DNS management disabled by default.
  Rationale: it enables repeatable, reviewable changes while avoiding accidental overwrites of existing tunnel routes until explicitly opted-in.
  Date/Author: 2025-12-18 / Codex

## Outcomes & Retrospective

- (Not started) Expected outcome is centralized OAuth protection for all exposed hostnames with a repeatable workflow for adding new ones.

## Context and Orientation

This repo is a GitOps-style homelab setup targeting k3s on Debian and FluxCD, with Kubernetes manifests under `apps/` and cluster wiring under `clusters/`.

Relevant pieces for this plan:

- Cloudflare Tunnel client (cloudflared) is deployed as a Kubernetes `Deployment`:

  - `apps/cloudflared/deployment.yaml` defines `infra/cloudflared` running `cloudflared tunnel ... run --token ...`.
  - `apps/cloudflared/secrets/tunnel-token.sops.yaml` stores the tunnel token (SOPS-encrypted).

- Traefik is installed via Flux HelmRelease and is the in-cluster reverse proxy / ingress controller:

  - `apps/traefik/helmrelease.yaml` installs Traefik in the `infra` namespace.
  - Ingress objects for apps typically point to Traefik’s `websecure` entrypoint and request certificates from cert-manager.

- Hostnames currently present in this repo (as of now) include:

  - `kan.def4alt.com` (`apps/kan/ingress.yaml`)
  - `papers.def4alt.com` (`apps/paperless/ingress.yaml`)
  - `photos.def4alt.com` (`apps/immich/ingress.yaml`)
  - `pihole.def4alt.com` (`apps/pi-hole/ingress.yaml`)
  - `home.def4alt.com` (`apps/home-assistant/helmrelease.yaml`)

Definitions used in this plan:

- “Cloudflare Tunnel”: a long-lived outbound connection from `cloudflared` to Cloudflare, used to serve public hostnames without opening inbound ports on the home network.
- “Cloudflare Access”: Cloudflare Zero Trust feature that requires users (or service-to-service clients) to authenticate before Cloudflare forwards traffic to the origin.
- “OAuth provider”: the identity provider (IdP) Cloudflare uses to log users in (for example Google Workspace, GitHub, Azure AD). Cloudflare calls this an “identity provider”.
- “SNI” (Server Name Indication): a field in the TLS handshake that indicates which hostname the client wants; Traefik uses it to select the correct certificate/router for HTTPS.

## Plan of Work

### Milestone 1: Inventory and policy design

At the end of this milestone we will have a definitive list of which hostnames are exposed via Cloudflare, who is allowed to access them, and what the “break glass” fallback is if the OAuth provider is down.

Do the following:

1. Inventory current Ingress hostnames in Git by searching for `host:` entries under `apps/`.
2. Decide which of these hostnames are intended to be Internet-exposed through Cloudflare Tunnel versus LAN-only or Tailscale-only.
3. For each Internet-exposed hostname, assign an Access policy:

   - Allowed identities (for example: a specific email allowlist, or a “group” in the IdP).
   - Whether service tokens are required for non-browser automation (recommended: yes).
   - Any path-based bypass that is required (avoid if possible; prefer service tokens).

4. Decide the OAuth provider to use and the expected user identifiers:

   - If you want “only me”, a simple allowlist of one or more emails is enough.
   - If you want “family”, decide whether you will manage a Google Workspace / GitHub org, or just multiple emails.

5. Define the desired user experience:

   - Single shared login for all homelab apps (recommended), or per-app “separate” applications.
   - Session lifetime (for example: 8 hours) and whether to require re-auth for sensitive apps (for example: Home Assistant).

### Milestone 2: Configure a single pilot hostname end-to-end

At the end of this milestone, one chosen hostname (for example `kan.def4alt.com`) is protected by OAuth and demonstrably works for both browser access and CLI/API access.

In Cloudflare Zero Trust:

1. Ensure the tunnel exists and is connected. Confirm you can see the connector as “healthy”.
2. Create a “public hostname” route for the pilot hostname that forwards into the cluster to Traefik.

   Route settings to use:

   - Service type: HTTPS
   - URL: `https://traefik.infra.svc.cluster.local:443`
   - HTTP Host Header: the public hostname (for example `kan.def4alt.com`)
   - TLS Origin Server Name (SNI): the same public hostname (for example `kan.def4alt.com`)

   The intent is: Cloudflare connects to Traefik, but presents the hostname the user requested so Traefik routes to the correct Ingress and the certificate matches.

3. Configure an identity provider (OAuth) in Zero Trust (if not already configured).

   Minimal secure setup:

   - Use a dedicated Cloudflare API token / application registration owned by the homelab owner.
   - Restrict to an explicit list of allowed email addresses or a managed group.

4. Create a Cloudflare Access “self-hosted application” for the pilot hostname and attach a policy:

   - Default action: “Allow” for the allowlist/group.
   - Create a “Block” catch-all policy for everyone else.
   - If you have automated clients, create a policy for “Service Auth” and issue a service token.

5. Validate:

   - In a browser, open the pilot URL and confirm you see the Access login page, then the app after login.
   - In a private/incognito browser, confirm a user outside the allowlist cannot access.
   - With `curl`, confirm a request without auth does not reach the origin:

     Expected shape:

       curl -I https://kan.def4alt.com
       HTTP/2 302
       location: https://<your-team>.cloudflareaccess.com/...

   - If using service tokens, validate API access:

       curl -I https://kan.def4alt.com \
         -H "CF-Access-Client-Id: <id>" \
         -H "CF-Access-Client-Secret: <secret>"

### Milestone 3: Roll out to all exposed hostnames

At the end of this milestone, every hostname intended to be Internet-reachable through the tunnel is protected by an Access application/policy, and has a correct tunnel route to Traefik.

Repeat the Milestone 2 process for each hostname, reusing the same identity provider and (if desired) shared policies:

- `papers.def4alt.com`
- `photos.def4alt.com`
- `pihole.def4alt.com`
- `home.def4alt.com`

For services with special traffic patterns, validate explicitly:

- Home Assistant: websockets and long-lived connections.
- Immich / Nextcloud: large uploads and long requests.

If anything fails, adjust tunnel “origin request” options, but keep the security posture:

- Prefer HTTPS to Traefik.
- Avoid disabling TLS verification unless there is no other feasible route; if you must disable it, document why and what you will do to restore verification.

### Milestone 4: Operationalize (repeatable workflow + break-glass)

At the end of this milestone, adding a new protected app is a small, repeatable process, and there is a safe recovery path if Cloudflare Access configuration is broken.

1. Define a break-glass procedure that does not require editing Kubernetes manifests:

   - Preferred: keep the DNS record and tunnel route, but temporarily disable the Access policy to restore access.
   - Alternative: temporarily remove the public hostname route in the tunnel to make the service unreachable from the Internet while you fix Access.

2. Create service tokens for non-interactive clients (for example: mobile apps that cannot complete an OAuth flow, health checks, or API scripts), and store them securely (SOPS-encrypted in-repo only if you are sure you want them in Git).

3. Decide whether you want to codify Cloudflare configuration as Infrastructure-as-Code:

   - If yes: add a Terraform module to this repo that manages Access apps/policies and tunnel public hostnames, and document how to apply it safely.
   - If no: document the “click path” in Cloudflare so the process is reproducible.

## Concrete Steps

Run these commands from the repository root (`/Users/def4alt/source/homelab`) to discover what needs protecting:

1. List all Kubernetes hostnames defined in Git:

     rg -n "host:" apps

2. For each resulting file, inspect the Ingress to see whether it is intended to be externally reachable and whether it is TLS-only (`websecure`):

     sed -n '1,160p' apps/<app>/ingress.yaml

3. Confirm the `cloudflared` deployment is token-mode (so routing is done in Cloudflare):

     sed -n '1,200p' apps/cloudflared/deployment.yaml

When implementing changes, validate from a machine that can reach the public Internet:

     curl -I https://<hostname>

## Validation and Acceptance

Acceptance criteria for this plan:

1. For each intended Internet-exposed hostname, an unauthenticated request does not reach the origin service and is instead redirected to Cloudflare Access login (or returns a 403 from Cloudflare Access).
2. After logging in via the chosen OAuth provider, the app loads and behaves normally.
3. Service-to-service automation that must access protected hostnames works only with explicit service tokens (or another deliberate non-interactive auth mechanism), not anonymously.
4. Removing or disabling an Access policy immediately prevents access from the Internet (proving that protection is effective and centralized).

## Idempotence and Recovery

This work should be safe to retry because it is primarily configuration in Cloudflare:

- Creating tunnel routes and Access apps/policies is additive; you can disable or delete them to rollback.
- If you accidentally lock yourself out, use the break-glass procedure from Milestone 4.

Avoid coupling rollback to Kubernetes changes. The in-cluster manifests should remain stable; only the Cloudflare “edge configuration” should change when enabling/disabling protection.

## Artifacts and Notes

When implementing this plan, capture small evidence snippets here:

- `curl -I` output showing redirect to Access before login.
- Screenshot or note of successful login and app load.
- If any service required special tunnel settings (timeouts, websockets), record the exact settings and why.

## Interfaces and Dependencies

Dependencies outside the cluster:

- A Cloudflare account with Zero Trust enabled and a connected Cloudflare Tunnel.
- An OAuth-capable identity provider configured in Cloudflare Zero Trust (Google, GitHub, Azure AD, etc).

Dependencies inside the cluster (already present in this repo):

- Traefik Ingress controller (`apps/traefik/helmrelease.yaml`).
- cert-manager issuing certificates for the hostnames (`apps/cert-manager` and `apps/cert-manager-issuers`).
- cloudflared connector (`apps/cloudflared/deployment.yaml`).

If future work decides to codify Cloudflare config as code, the dependency will expand to include Terraform (or another IaC tool) and a safe secret-management approach for Cloudflare API tokens.
