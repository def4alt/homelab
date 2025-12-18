locals {
  hostnames = toset([
    "boards.${var.base_domain}",
    "papers.${var.base_domain}",
    "photos.${var.base_domain}",
    "pihole.${var.base_domain}",
    "home.${var.base_domain}",
  ])

  hostnames_sorted    = sort(tolist(local.hostnames))
  tunnel_cname_target = "${var.tunnel_id}.cfargotunnel.com"
}
