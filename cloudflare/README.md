# Cloudflare Zero Trust (Tunnel) as Code

This folder is a small OpenTofu project to manage:

- Cloudflare Tunnel hostname routing to the in-cluster Traefik service for the HTTP apps.
- A plain DNS `CNAME` for `minecraft.def4alt.com` that points at the Tailscale hostname for the Minecraft host.

It is intentionally opt-in for tunnel routing so you can keep managing tunnel routes in the Cloudflare UI until you are ready to have OpenTofu own them.

## Prereqs

- OpenTofu installed locally.
- A Cloudflare API token provided via `CLOUDFLARE_API_TOKEN` (recommended) or `cloudflare_api_token` in `terraform.tfvars`, with permissions sufficient for:
  - Tunnel configuration (only if you enable tunnel config management)
  - DNS (only if you enable DNS management)
- You know your Cloudflare `account_id`, `zone_id`, and tunnel UUID (`tunnel_id`).
- The Tailscale host `perun` must be serving Minecraft on TCP 25565.

## Quick start

From repo root:

    cd cloudflare
    tofu init

Create a `terraform.tfvars` (not committed) with at least:

    account_id      = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    zone_id         = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    tunnel_id       = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    base_domain     = "def4alt.com"

You can start from `cloudflare/terraform.tfvars.example`.

Then:

    tofu plan
    tofu apply

## What this manages

Optional flags:

- `manage_tunnel_config = true` will manage tunnel ingress rules for the public HTTP hostnames, forwarding to Traefik at `https://traefik.infra.svc.cluster.local:443` and setting both Host header and TLS SNI to the requested hostname.
- `manage_dns = true` will create `CNAME` records for the HTTP hostnames.
- `api-photos.def4alt.com` and `minecraft.def4alt.com` are intentionally kept on the Tailscale path and are not part of the Cloudflare tunnel ingress set.
- `minecraft.def4alt.com` resolves to the Tailscale hostname for `perun`, and Tailscale Serve on the host forwards TCP 25565 to the Minecraft service.

## Operational notes

- Break-glass: set `manage_tunnel_config = false` and/or `manage_dns = false` and apply, or manage those settings in the Cloudflare UI while you recover.
- If you change the Minecraft host or Tailscale target later, update the `cname_overrides` map in `locals.tf` and re-run OpenTofu so the DNS record stays correct.
