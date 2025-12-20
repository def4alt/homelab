---
name: pocketbase-backend
description: Deploy PocketBase behind Authentik at backend.def4alt.com
---

# Plan

Deploy PocketBase as a new app in k3s with persistent storage, Authentik-protected ingress, and Cloudflare DNS/Tunnel wiring, following the repo's GitOps patterns.

## Requirements
- PocketBase Deployment/Service/Ingress in a dedicated namespace.
- 10Gi PVC for PocketBase data.
- Authentik forward-auth middleware on the ingress.
- DNS/Tunnel hostname `backend.def4alt.com` managed via Cloudflare Terraform.
- Admin email set to `andrii.olkhovych@pm.me` and password stored in SOPS secret.

## Scope
- In: new `apps/pocketbase/` manifests, namespace, Flux overlay, Cloudflare hostnames.
- Out: user management configuration beyond initial admin credentials.

## Files and entry points
- `apps/pocketbase/` (deployment, service, ingress, pvc, secret, kustomization)
- `apps/namespaces/` (new namespace)
- `clusters/home/overlays/apps/pocketbase.yaml`
- `clusters/home/overlays/kustomization.yaml`
- `cloudflare/locals.tf`

## Data model / API changes
- New PocketBase admin credentials stored in SOPS secret.

## Action items
[x] Add namespace for PocketBase and wire into namespaces kustomization.
[x] Add PVC (10Gi) for PocketBase data.
[x] Add Deployment/Service using the official PocketBase image.
[x] Create SOPS secret with admin email/password and inject into the deployment.
[x] Add Ingress for `backend.def4alt.com` with Authentik middleware + TLS.
[x] Wire Flux Kustomization for the new app and add Cloudflare hostname.
[ ] Validate deployment health, ingress reachability, and admin login.

## Progress updates
- 2025-12-20: Added PocketBase namespace, PVC, deployment/service/ingress, and Flux wiring; Cloudflare hostname set to `backend.def4alt.com`.
- 2025-12-20: Added SOPS secret for admin bootstrap and init container that creates the admin user on startup.

## Testing and validation
- `kubectl -n pocketbase get pods,svc,ingress` shows ready.
- Browse `https://backend.def4alt.com/_/` and log in with admin credentials.
- Confirm data persists after pod restart.

## Risks and edge cases
- Authentik may interfere with PocketBase admin UI if callback URLs need adjustment.
- Initial admin creation needs correct env vars for the selected image.

## Open questions
- None.
