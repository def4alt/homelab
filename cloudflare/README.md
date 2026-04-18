# Cloudflare Zero Trust (Tunnel) as Code

This folder is a small Terraform project to manage:

- (Optional) Cloudflare Tunnel hostname routing to the in-cluster Traefik service.

It is intentionally opt-in for tunnel routing so you can keep managing tunnel routes in the Cloudflare UI until you are ready to have Terraform own them.

## Prereqs

- Terraform installed locally.
- A Cloudflare API token provided via `CLOUDFLARE_API_TOKEN` (recommended) or `cloudflare_api_token` in `terraform.tfvars`, with permissions sufficient for:
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

You can start from `cloudflare/terraform.tfvars.example`.

Then:

    terraform plan
    terraform apply

## What this manages

Optional flags:

- `manage_tunnel_config = true` will manage tunnel ingress rules for the public hostnames, forwarding to Traefik at `https://traefik.infra.svc.cluster.local:443` and setting both Host header and TLS SNI to the requested hostname.
- `manage_dns = true` will create `CNAME` records for all managed hostnames. `api-photos.def4alt.com` is intentionally kept on the Tailscale path and is not part of the Cloudflare tunnel ingress set.

## Operational notes

- Break-glass: set `manage_tunnel_config = false` and/or `manage_dns = false` and apply, or manage those settings in the Cloudflare UI while you recover.
