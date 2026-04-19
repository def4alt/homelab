resource "cloudflare_record" "cname" {
  for_each = var.manage_dns ? local.all_hostnames : toset([])

  zone_id         = var.zone_id
  name            = each.key == var.base_domain ? "@" : trimsuffix(each.key, ".${var.base_domain}")
  type            = "CNAME"
  content         = lookup(local.cname_overrides, each.key, local.tunnel_cname_target)
  allow_overwrite = true
  ttl             = 1
  proxied         = contains(local.unproxied_hostnames, each.key) ? false : true
}

