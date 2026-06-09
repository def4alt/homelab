# Add Transmission with a WireGuard Sidecar on `clusters/home`

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the home cluster has a dedicated `transmission` workload whose entire pod network runs through a WireGuard sidecar instead of changing routing on the host NixOS/k3s node. The repo owns the namespace, local storage, encrypted WireGuard credentials, workload manifests, and Flux overlay wiring so the setup remains GitOps-managed and easy to reason about.

## Progress

- [x] (2026-06-09) Inspect existing home-cluster app, namespace, local-storage, and SOPS patterns in this repo.
- [x] (2026-06-09) Create the `transmission` app manifests, namespace, local PV/PVC, and encrypted WireGuard secret.
- [x] (2026-06-09) Add Flux overlay wiring for `clusters/home` and verify Kustomize renders cleanly with `kubectl kustomize`.
- [x] (2026-06-09) Expose the Transmission web UI at `sea.def4alt.com` through Traefik, cert-manager, Authentik forward-auth, and the Cloudflare hostname list.
- [x] (2026-06-09) Record final decisions and validation outcomes in this plan.

## Surprises & Discoveries

- The home cluster already has a `manual-local` StorageClass plus explicit hostPath-backed PersistentVolumes under `apps/local-storage/`, so this app can follow an existing local-disk pattern instead of introducing a new storage abstraction.
- `clusters/home/kustomization.yaml` currently points at `modes/apps`, which in turn includes `clusters/home/overlays`, so adding a new home app still means wiring it through `clusters/home/overlays/`.
- The WireGuard export archive is present at `~/Documents/wireguard-export.zip` and contains a single `Home.conf` client profile with a full-tunnel peer, home-LAN DNS (`192.168.88.1`), and endpoint `185.30.200.16:13231`.
- The repo does not define SOPS creation rules, so creating a new encrypted secret required an explicit `sops --config /dev/null --encrypt --age ... --encrypted-regex '^(data|stringData)$'` invocation instead of relying on `.sops.yaml`.

## Decision Log

- Decision: Keep WireGuard scoped to a sidecar in the Transmission pod instead of configuring it on the node.
  Rationale: The user explicitly wants torrent traffic isolated from k3s, Flux, host DNS, and control-plane networking.
  Date/Author: 2026-06-09 / Codex

- Decision: Use a host-local `manual-local` PV/PVC for torrent state and downloads.
  Rationale: Large torrent payloads do not benefit much from replicated storage here, and the repo already has a local-storage pattern for single-node stateful apps.
  Date/Author: 2026-06-09 / Codex

- Decision: Expose only a `ClusterIP` Service for the Transmission web UI in this change.
  Rationale: The service object remains internal while Traefik terminates public access through an authenticated ingress, which matches the repo’s existing home-cluster pattern.
  Date/Author: 2026-06-09 / Codex

- Decision: Drop the exported `DNS = 192.168.88.1` value instead of carrying it into the pod deployment.
  Rationale: That DNS target points back at the home LAN and defeats the goal of a torrent-only VPN egress path.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

The repo now contains a complete GitOps skeleton for a Transmission-on-WireGuard pod on `clusters/home`: namespace manifest, local PV/PVC, encrypted WireGuard secret, app manifests, and the Flux overlay entry. Local render validation succeeded for `apps/transmission`, `apps/local-storage`, and `clusters/home/overlays`.

The remaining unknown is runtime behavior on the live cluster. I did not reconcile Flux or inspect the running pod, so Gluetun-specific runtime details such as tunnel establishment, firewall behavior, and any provider-specific environment mismatches remain unverified until the manifests are applied.

## Context and Orientation

The repository uses Flux `Kustomization` objects under `clusters/home/overlays/` to point at app directories in `apps/`. Namespaces are handled separately in `apps/namespaces`, and local-disk hostPath PVs are defined centrally in `apps/local-storage`.

For this app, the desired runtime model is a single pod with shared networking across two containers:

- `gluetun` provides the WireGuard tunnel and firewall / kill-switch behavior.
- `transmission` runs the torrent client in the same pod network namespace so it does not have an alternate route outside the VPN tunnel.

The provided WireGuard profile looks like a client config that should be translated into encrypted secret values, not committed as a raw `.conf` file. The exported DNS value should not be reused for torrent-only VPN egress because it points back at the home LAN.

## Plan of Work

Create a new `apps/transmission` directory containing a `Deployment`, `Service`, `PersistentVolumeClaim`, `kustomization.yaml`, and an encrypted secret with the WireGuard parameters extracted from the user-provided client config. The deployment should run `gluetun` and `transmission` in the same pod, mount one PVC for config and downloads, and use conservative resource requests/limits appropriate for a homelab node.

Add a new namespace manifest under `apps/namespaces`, add a matching hostPath-backed PV under `apps/local-storage`, and then add a Flux app overlay under `clusters/home/overlays/apps/` with dependencies on `namespaces` and `local-storage`.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1. Add the app manifests:
   - `apps/transmission/kustomization.yaml`
   - `apps/transmission/deployment.yaml`
   - `apps/transmission/service.yaml`
   - `apps/transmission/pvc.yaml`
   - `apps/transmission/secrets/wireguard.sops.yaml`

2. Add namespace and local storage:
   - `apps/namespaces/namespace-transmission.yaml`
   - Update `apps/namespaces/kustomization.yaml`
   - `apps/local-storage/pv-transmission.yaml`
   - Update `apps/local-storage/kustomization.yaml`

3. Wire Flux for the home cluster:
   - `clusters/home/overlays/apps/transmission.yaml`
   - Update `clusters/home/overlays/kustomization.yaml`

4. Validate:
   - Run `kustomize build apps/transmission`
   - Run `kustomize build apps/local-storage`
   - Run `kustomize build clusters/home/overlays`

## Validation and Acceptance

After Flux reconciles the change, the expected outcomes are:

- The `transmission` namespace exists.
- The local PV and PVC bind successfully.
- The Transmission pod starts with both containers in one network namespace.
- Torrent traffic is scoped to the WireGuard sidecar path rather than the host node.
- The Transmission web UI is reachable through the internal service without exposing torrent traffic separately.

## Idempotence and Recovery

This change is safe to re-apply through Flux. If the VPN details need to change, update only the SOPS-managed secret and let Flux roll the deployment.

If the chosen local storage path or capacity is wrong, update the PV/PVC manifests carefully before data is written. Because the PV uses a `Retain` reclaim policy, deleting the claim should not destroy host data.

## Interfaces and Dependencies

- Flux app overlays live in `clusters/home/overlays/apps/`.
- Namespace manifests live in `apps/namespaces/`.
- Local hostPath PVs live in `apps/local-storage/`.
- The new Flux app overlay should depend on `namespaces` and `local-storage`.

Change note: Initial ExecPlan created for a home-cluster Transmission deployment with a WireGuard sidecar and local storage.
