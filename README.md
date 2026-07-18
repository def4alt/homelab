# Homelab

Single-node NixOS and k3s homelab running on `perun`, reconciled by FluxCD from
`clusters/home`.

## NixOS

The flake exposes only `nixosConfigurations.perun`. To install from a NixOS
installer or rescue environment:

```sh
nix run github:nix-community/nixos-anywhere -- --flake '.#perun' \
  --target-host nixos@<installer-ip> --build-on-remote
```

Review `nixos/configuration.nix`, `nixos/hardware-configuration.nix`, and
`nixos/disko-config.nix` before installation.

## Kubernetes

`apps/` contains application and infrastructure manifests. `clusters/home`
contains the active Flux configuration. The inactive `clusters/hetzner` root
includes only its Flux bootstrap; its dormant overlays are not reconciled.

The cluster includes:

- Infrastructure: Traefik, MetalLB, cert-manager, CloudNativePG, Cloudflared,
  local storage, and JuiceFS.
- Observability: Prometheus, Alertmanager, Grafana, Loki, Alloy, and Blackbox
  Exporter.
- Applications: Authentik, Blog, Glance, Home Assistant, Immich, Linkding,
  Minecraft, Paperless, Pi-hole, Transmission, Jellyfin, Prowlarr, Radarr, and
  Sonarr.

Persistent hostPath volumes are declared under `apps/local-storage`. Workloads
that require shared storage use JuiceFS.

## Secrets

Flux Kustomizations containing encrypted manifests use SOPS with the Age
recipient declared in `.sops.yaml`. Install the matching private key as:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=~/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

Sensitive configuration is stored in SOPS-encrypted manifests:

- Application credentials under the relevant `apps/<name>/secrets` directory.
- Grafana and Alertmanager configuration under `apps/monitoring/secrets`.
- Shared CNPG backup credentials under `apps/secrets`.
- Home Authentik outpost credentials under `apps/modes/home/traefik-auth/secrets`.

Never commit decrypted secret material.

## Cloudflare

`cloudflare/` is an OpenTofu project for optional Tunnel ingress and DNS
management. Configure `terraform.tfvars`, then run:

```sh
tofu -chdir=cloudflare init
tofu -chdir=cloudflare plan
tofu -chdir=cloudflare apply
```

See `cloudflare/README.md` for routing details.

## Operations

- Switch between application and Minecraft modes with
  `./scripts/switch-mode <apps|minecraft>` and commit the resulting change.
- See `docs/operations/home-modes.md` for mode behavior and CNPG caveats.
- Prefer GitOps changes, validate affected Kustomize paths, run
  `git diff --check`, then reconcile and verify Flux, pods, and volumes.
