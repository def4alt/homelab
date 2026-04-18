# ExecPlan: Route Immich uploads through Tailscale

## Goal
Keep `photos.def4alt.com` public behind Cloudflare and move `api-photos.def4alt.com` off Cloudflare’s data path so large Immich uploads can reach Traefik over Tailscale instead.

## Scope
- Keep the Immich deployment unchanged.
- Make `api-photos.def4alt.com` resolve to the Tailscale node, not the Cloudflare tunnel.
- Configure the existing Tailscale node to forward TCP 443 to Traefik.
- Ensure Cloudflare tunnel ingress no longer includes the upload hostname.

## Approach
1. Split Cloudflare hostname management into public and tailnet-only sets.
2. Remove `api-photos.def4alt.com` from Cloudflare tunnel ingress rules.
3. Add Tailscale `serve` configuration to the infra Tailscale DaemonSet so the node exposes `api-photos.def4alt.com` over the tailnet and forwards traffic to Traefik on `192.168.88.193:443`.

## Validation
- `kubectl kustomize` succeeds for updated manifests.
- Flux reconciles the updated Kustomizations.
- `tailscale serve status` shows the TCP forwarding rule.
- `api-photos.def4alt.com` resolves to the Tailscale hostname and uploads bypass Cloudflare.

## Status
- Completed

## Notes
- `api-photos.def4alt.com` is excluded from the Cloudflare tunnel ingress set.
- The Tailscale node now runs on the host via NixOS, and `tailscale serve` forwards TCP 443 to Traefik through `127.0.0.1:31818`.
- The k3s Tailscale DaemonSet has been removed from GitOps.
- The host tailnet node now uses the plain `perun` name again.
