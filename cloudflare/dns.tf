resource "cloudflare_record" "cname" {
  for_each = var.manage_dns ? setunion(local.public_hostnames, local.tailnet_hostnames, toset([local.shell_hostname])) : toset([])

  zone_id         = var.zone_id
  name            = each.key == var.base_domain ? "@" : trimsuffix(each.key, ".${var.base_domain}")
  type            = "CNAME"
  content         = lookup(local.cname_overrides, each.key, local.tunnel_cname_target)
  allow_overwrite = true
  ttl             = 1
  proxied         = contains(local.unproxied_hostnames, each.key) ? false : true
}

resource "cloudflare_record" "minecraft_a" {
  count = var.manage_dns ? 1 : 0

  zone_id         = var.zone_id
  name            = trimsuffix(local.minecraft_hostname, ".${var.base_domain}")
  type            = "A"
  content         = local.minecraft_tailnet_ip
  allow_overwrite = true
  ttl             = 1
  proxied         = false
}

