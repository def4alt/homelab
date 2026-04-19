# Cloudflare Zero Trust (Tunnel) as Code

This folder is a small OpenTofu project to manage:

- Cloudflare Tunnel hostname routing to the in-cluster Traefik service for the HTTP apps.
- A plain DNS `A` record for `minecraft.def4alt.com` that points directly at the Minecraft server's MetalLB address.

It is intentionally opt-in for tunnel routing so you can keep managing tunnel routes in the Cloudflare UI until you are ready to have OpenTofu own them.

## Prereqs

- OpenTofu installed locally.
- A Cloudflare API token provided via `CLOUDFLARE_API_TOKEN` (recommended) or `cloudflare_api_token` in `terraform.tfvars`, with permissions sufficient for:
  - Tunnel configuration (only if you enable tunnel config management)
  - DNS (only if you enable DNS management)
- You know your Cloudflare `account_id`, `zone_id`, and tunnel UUID (`tunnel_id`).
- For Minecraft DNS, you also need the MetalLB IP that the server uses inside the LAN.

## Quick start

From repo root:

    cd cloudflare
    tofu init

Create a `terraform.tfvars` (not committed) with at least:

    account_id      = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    zone_id         = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    tunnel_id       = "cccccccc-cccc-cccc-cccc-cccccccccccc"
    base_domain     = "def4alt.com"
    minecraft_lb_ip = "192.168.88.194"

You can start from `cloudflare/terraform.tfvars.example`.

Then:

    tofu plan
    tofu apply

## What this manages

Optional flags:

- `manage_tunnel_config = true` will manage tunnel ingress rules for the public HTTP hostnames, forwarding to Traefik at `https://traefik.infra.svc.cluster.local:443` and setting both Host header and TLS SNI to the requested hostname.
- `manage_dns = true` will create `CNAME` records for the HTTP hostnames and, when `minecraft_lb_ip` is set, an `A` record for `minecraft.def4alt.com` that points directly at the Minecraft server.
- `api-photos.def4alt.com` is intentionally kept on the Tailscale path and is not part of the Cloudflare tunnel ingress set.
- `minecraft.def4alt.com` is not routed through Cloudflare Tunnel because Minecraft is raw TCP traffic, not HTTP.

## Operational notes

- Break-glass: set `manage_tunnel_config = false` and/or `manage_dns = false` and apply, or manage those settings in the Cloudflare UI while you recover.
- If you change the Minecraft service IP later, update `minecraft_lb_ip` and re-run OpenTofu so the DNS record stays correct.
