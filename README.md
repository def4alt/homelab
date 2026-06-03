# Homelab

## Installation

### NixOS baseline

This repo now represents two independent NixOS sites:

- `perun` — the home host that runs the `clusters/home` k3s + Flux stack
- `zorya` — the Hetzner host that is intended to run the `clusters/hetzner` k3s + Flux stack

The flake in `nixos/flake.nix` exposes both hosts. To install either machine, boot the target with a NixOS installer or rescue image and run `nixos-anywhere` against the desired flake output.

Home host example:

```sh
nix run github:nix-community/nixos-anywhere -- --flake '.#perun' \
  --target-host nixos@<installer-ip> --build-on-remote
```

Hetzner host example:

```sh
nix run github:nix-community/nixos-anywhere -- --flake '.#zorya' \
  --target-host root@46.62.137.102 --build-on-remote
```

Before running either command, review `nixos/configuration.nix` plus the host-specific hardware and disk files. `perun` uses `nixos/hardware-configuration.nix` and `nixos/disko-config.nix`. `zorya` uses `nixos/hosts/zorya/hardware-configuration.nix` and `nixos/hosts/zorya/disko-config.nix`. The flake also pulls in `disko` so the installed partitioning matches the source-controlled layout.

### Cloudflare tunnels

`cloudflare/` is a small Terraform project that can own the Cloudflare Tunnel and optional DNS records forwarding to Traefik. Toggle the `manage_tunnel_config` and `manage_dns` flags in `terraform.tfvars` to choose how much Terraform should manage, fill in `account_id`, `zone_id`, `tunnel_id`, and optionally `base_domain`, then run `terraform init && terraform apply` from `cloudflare/`.

## Kubernetes stack

### k3s + Flux

k3s runs on both NixOS hosts, but each host is its own independent single-node cluster. FluxCD reconciles the home cluster from `clusters/home` and the Hetzner cluster from `clusters/hetzner`. The `apps/` directory remains the canonical source of Traefik, Cert-Manager, infra helpers, and the applications themselves; each cluster chooses which app directories to reconcile through its own Flux overlays.

All infra overlays set `spec.decryption.provider: sops`, so Flux decrypts the secrets stored under `apps/*/secrets/*.sops.yaml` using a dedicated Age key. The cluster must contain the namespace-scoped secret `flux-system/sops-age` that holds the private key to decrypt those secrets.

Create the key pair (if you do not already have one) with:

```sh
mkdir -p ~/.config/sops/age
age-keygen -o ~/.config/sops/age/keys.txt
```

Add the public key (seen in `.sops.yaml` as `age1843v8f2y…94q24x8cz`) to the list Flux should trust, encrypt secrets with `sops --age <your-key-id> ...`, then give Flux the private half:

```sh
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.key=~/.config/sops/age/keys.txt \
  --dry-run=client -o yaml | kubectl apply -f -
```

Once that secret exists, Flux can reconcile the overlays under whichever cluster path you bootstrap (`clusters/home/overlays` or `clusters/hetzner/overlays`) without further manual steps.

## Secrets to set

Every mutable piece of data lives under `apps/*/secrets/*.sops.yaml`. Populate these files with values encrypted by the same Age key before Flux can bring up the associated services:

- `apps/restic/secrets/restic-credentials.sops.yaml` – restic credentials for remote/Backblaze B2 uploads.
- `apps/cloudflared/secrets/tunnel-token.sops.yaml` – Cloudflare Tunnel token for `cloudflared`.
- `apps/home-assistant/secrets/postgres-auth.sops.yaml` – Home Assistant Postgres user/password.
- `apps/home-assistant/secrets/home-assistant-secrets.sops.yaml` – Home Assistant-wide secrets (API tokens, webhook secrets, etc.).
- `apps/cert-manager-issuers/secrets/cloudflare-dns.sops.yaml` – Cloudflare API token for DNS-01 challenges.
- `apps/tailscale/secrets/auth.sops.yaml` – Tailscale pre-auth key for the daemonset.
- `apps/pi-hole/secrets/web-password.sops.yaml` – Pi-hole admin password.
- `apps/longhorn/secrets/backup-target-credentials.sops.yaml` – S3-compatible credentials for Longhorn backups.
- `apps/paperless/secrets/postgres-auth.sops.yaml` – Paperless Postgres user/password.
- `apps/paperless/secrets/redis-auth.sops.yaml` – Paperless Redis authentication.
- `apps/paperless/secrets/paperless-secrets.sops.yaml` – Paperless application secrets.
- `apps/secrets/cnpg-barman-s3.sops.yaml` – shared CNPG backup AWS credentials.
- `apps/juicefs/secrets/juicefs-auth.sops.yaml` – JuiceFS metadata DB credentials and B2 access settings.
- `apps/immich/secrets/postgres-auth.sops.yaml` – Immich Postgres credentials.
- `apps/immich/secrets/redis-auth.sops.yaml` – Immich Redis credentials.
- `apps/authentik/secrets/postgres-auth.sops.yaml` – Authentik Postgres credentials.
- `apps/authentik/secrets/authentik-config.sops.yaml` – Authentik config (emails, webhooks, etc.).
- `apps/shell/secrets/ssh-authorized-keys.sops.yaml` – SSH public keys for shell access.

Encrypt them with `sops --age <key-id> ...` and commit only the encrypted files so Flux can decrypt them when the `sops-age` secret matches the key pair you used.

## Services

- **Infrastructure**: Traefik (+ CRDs), Cert-Manager (and Issuers), MetalLB (+ config), Longhorn (+ recurring backup jobs), CloudNativePG clusters, JuiceFS CSI driver + metadata DB, Cloudflared tunnel ingress, and monitoring helpers.
- **Applications**: Authentik SSO, Home Assistant, Paperless, Blog on def4alt.com, Glance dashboard, Immich, Pi-hole, and Minecraft.
- **Helpers**: `apps/namespaces` ensures consistent namespaces, `apps/cnpg` contains shared Postgres helpers, and `apps/secrets` holds supporting credentials such as the shared CNPG Barman AWS key.

Keeping the cluster overlays aligned with `apps/` lets Flux keep each site in sync once the secrets are in place.
