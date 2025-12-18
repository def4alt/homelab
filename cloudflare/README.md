# Cloudflare Zero Trust (Tunnel + Access) as Code

This folder is a small Terraform project to manage:

- Cloudflare Access (OAuth gate) for homelab hostnames.
- (Optional) Cloudflare Tunnel hostname routing to the in-cluster Traefik service.

It is intentionally opt-in for tunnel routing so you can start by managing only Access policies without risking an accidental overwrite of your existing tunnel configuration.

## Prereqs

- Terraform installed locally.
- A Cloudflare API token provided via `CLOUDFLARE_API_TOKEN` (recommended) or `cloudflare_api_token` in `terraform.tfvars`, with permissions sufficient for:
  - Zero Trust Access apps/policies
  - Tunnel configuration (only if you enable tunnel config management)
  - DNS (only if you enable DNS management)
- You know your Cloudflare `account_id`, `zone_id`, and tunnel UUID (`tunnel_id`).

## Quick start

From repo root:

    cd cloudflare
    terraform init

Create a `terraform.tfvars` (not committed) with at least:

    account_id      = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    zone_id         = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    tunnel_id       = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    base_domain     = "def4alt.com"
    allowed_emails  = ["you@example.com"]

You can start from `cloudflare/terraform.tfvars.example`.

Then:

    terraform plan
    terraform apply

## What this manages

By default, this creates one Cloudflare Access application and policy set per hostname listed in `locals.tf`.

Optional flags:

- `manage_tunnel_config = true` will manage tunnel ingress rules for those hostnames, forwarding to Traefik at `https://traefik.infra.svc.cluster.local:443` and setting both Host header and TLS SNI to the requested hostname.
- `manage_dns = true` will create `CNAME` records for each hostname pointing at `<tunnel_id>.cfargotunnel.com` (useful if you want Terraform to own DNS as well).

## Operational notes

- Identity provider (Google/GitHub/etc.) configuration typically lives in Cloudflare Zero Trust settings and is not managed here. This project assumes you already have at least one IdP configured.
- Break-glass: you can disable Access enforcement by `terraform destroy` for Access resources (or toggling a variable and applying), without changing anything in Kubernetes.
