# Homelab

## Installation

### NixOS baseline

This repo represents the full stack for a single NixOS host. The flake in `nixos/flake.nix` defines one node called `perun`, and the rest of the repo assumes that host name. To reproduce the same setup on bare metal, boot the target machine with the standard NixOS installer and run:

```sh
nix run github:nix-community/nixos-anywhere -- --flake '.#perun' \
  --target-host nixos@<installer-ip> --build-on-remote
```

Before running the command you can tweak `nixos/configuration.nix`, `hardware-configuration.nix`, or any module under `nixos/`. The flake also pulls in `disko` so the disk layout you install will match the source-controlled partitioning.

### Cloudflare tunnels

`cloudflare/` is a small Terraform project that can own the Cloudflare Tunnel and optional DNS records forwarding to Traefik. Toggle the `manage_tunnel_config` and `manage_dns` flags in `terraform.tfvars` to choose how much Terraform should manage, fill in `account_id`, `zone_id`, `tunnel_id`, and optionally `base_domain`, then run `terraform init && terraform apply` from `cloudflare/`.

## Kubernetes stack

### k3s + Flux

k3s runs on the NixOS host, and FluxCD reconciles everything under `clusters/home`. The `apps/` directory is the canonical source of Traefik, Cert-Manager, infra helpers, and the applications themselves; Flux is bootstrapped in `clusters/home/flux-system` and pulls overlays from `clusters/home/overlays`.

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

Once that secret exists, Flux can reconcile the overlays under `clusters/home/overlays` without further manual steps.

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
- `apps/kaneo/secrets/kaneo-secrets.sops.yaml` – Kaneo database credentials, auth secret, and database URL.
- `apps/secrets/cnpg-barman-s3.sops.yaml` – shared CNPG/backup S3 credentials.
- `apps/immich/secrets/postgres-auth.sops.yaml` – Immich Postgres credentials.
- `apps/immich/secrets/redis-auth.sops.yaml` – Immich Redis credentials.
- `apps/authentik/secrets/postgres-auth.sops.yaml` – Authentik Postgres credentials.
- `apps/authentik/secrets/authentik-config.sops.yaml` – Authentik config (emails, webhooks, etc.).

Encrypt them with `sops --age <key-id> ...` and commit only the encrypted files so Flux can decrypt them when the `sops-age` secret matches the key pair you used.

## Services

- **Infrastructure**: Traefik (+ CRDs), Cert-Manager (and Issuers), MetalLB (+ config), Longhorn (+ recurring backup jobs), CloudNativePG clusters, Cloudflared tunnel ingress, Tailscale daemonset, Restic backups.
- **Applications**: Authentik SSO, Home Assistant, Paperless, Kaneo project management, Blog on def4alt.com, Glance dashboard, Immich, Pi-hole, nanobot.
- **Helpers**: `apps/namespaces` ensures consistent namespaces, `apps/cnpg` contains shared Postgres helpers, and `apps/secrets` holds supporting credentials such as the CNPG Barman S3 key.

Keeping `clusters/home/overlays` aligned with `apps/` lets Flux keep every service in sync once the secrets are in place.
