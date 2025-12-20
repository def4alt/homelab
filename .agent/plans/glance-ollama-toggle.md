---
name: glance-ollama-toggle
description: Add a Glance dashboard toggle to scale Ollama via an in-cluster webhook
---

# Plan

Add a small in-cluster webhook service with minimal RBAC to scale the Ollama deployment, and surface it as a button/link on the Glance dashboard. This keeps control in GitOps while enabling on-demand power saving.

## Requirements
- A webhook endpoint in-cluster that can scale `deployment/ollama` up/down in `ai`.
- RBAC scoped to only allow scaling Ollama.
- Glance link/button that calls the webhook endpoint.
- Auth protection for the webhook endpoint.

## Scope
- In: webhook Deployment/Service/Ingress, RBAC, Glance config update.
- Out: full automation (schedulers), multi-app scaling, or external auth systems beyond existing Authentik/Traefik.

## Files and entry points
- `apps/glance/configmap.yaml` (add toggle link/button)
- New app folder for the webhook (e.g., `apps/ollama-toggle/`)
- `clusters/home/overlays/apps/ollama-toggle.yaml` (Flux wiring)

## Data model / API changes
- New HTTP endpoint: `POST /toggle` (or separate `/start` and `/stop`) to scale `ai/ollama`.

## Action items
[x] Choose webhook implementation (small container using Kubernetes API with service account).
[x] Add RBAC Role/RoleBinding limited to `deployments/scale` for `ollama` in `ai`.
[x] Create Deployment/Service/Ingress for the toggle webhook behind Authentik.
[x] Update Glance dashboard to include button/link for the toggle endpoint.
[x] Add Flux kustomization for the new webhook app.
[ ] Validate manual toggles scale Ollama up/down and Glance link works.

## Testing and validation
- `kubectl -n ai get deploy ollama` shows replicas change after button use.
- Webhook returns 2xx on success and is protected by Authentik.
- Glance button/link reachable and triggers scale action.

## Risks and edge cases
- Webhook could be abused if not protected by Authentik.
- Rapid toggling may leave Ollama pods terminating/starting while Flux health checks run.

## Open questions
- Preferred endpoint behavior: toggle, explicit start/stop, or both?
- Desired hostname for the webhook (e.g., `ollama-toggle.def4alt.com`)?

## Progress updates
- 2025-12-20: Added ollama toggle webhook (Python HTTP server) with minimal RBAC, service/ingress protected by Authentik, and Flux wiring; Glance now links to the toggle endpoint.
