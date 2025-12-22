locals {
  hostnames = toset([
    "auth.${var.base_domain}",
    "outpost.${var.base_domain}",
    "boards.${var.base_domain}",
    "docs.${var.base_domain}",
    "papers.${var.base_domain}",
    "photos.${var.base_domain}",
    "api-photos.${var.base_domain}",
    "dashboard.${var.base_domain}",
    "pihole.${var.base_domain}",
    "home.${var.base_domain}",
    "llm.${var.base_domain}",
    "later.${var.base_domain}",
  ])

  hostnames_sorted    = sort(tolist(local.hostnames))
  tunnel_cname_target = "${var.tunnel_id}.cfargotunnel.com"
}
