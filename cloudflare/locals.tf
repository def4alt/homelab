locals {
  hostnames = toset([
    "auth.${var.base_domain}",
    "papers.${var.base_domain}",
    "photos.${var.base_domain}",
    "api-photos.${var.base_domain}",
    "grafana.${var.base_domain}",
    "dashboard.${var.base_domain}",
    "prometheus.${var.base_domain}",
    "pihole.${var.base_domain}",
    "home.${var.base_domain}",
    "executor.${var.base_domain}",
    "projects.${var.base_domain}",
  ])

  cname_overrides = {
    "api-photos.${var.base_domain}" = "perun.tail6f3b0.ts.net"
  }

  unproxied_hostnames = toset([
    "api-photos.${var.base_domain}",
  ])

  hostnames_sorted    = sort(tolist(local.hostnames))
  tunnel_cname_target = "${var.tunnel_id}.cfargotunnel.com"
}
