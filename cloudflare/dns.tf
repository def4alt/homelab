resource "cloudflare_record" "cname" {
  for_each = var.manage_dns ? local.hostnames : toset([])

  zone_id = var.zone_id
  name    = trimsuffix(each.key, ".${var.base_domain}")
  type    = "CNAME"
  content = local.tunnel_cname_target
  allow_overwrite = true
  ttl     = 1
  proxied = true
}
