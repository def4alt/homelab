locals {
  public_hostnames = toset([
    "auth.${var.base_domain}",
    "papers.${var.base_domain}",
    "photos.${var.base_domain}",
    "grafana.${var.base_domain}",
    "dashboard.${var.base_domain}",
    "prometheus.${var.base_domain}",
    "pihole.${var.base_domain}",
    "home.${var.base_domain}",
    "executor.${var.base_domain}",
    "projects.${var.base_domain}",
    var.base_domain,
  ])

  tailnet_hostnames = toset([
    "api-photos.${var.base_domain}",
  ])

  all_hostnames = setunion(local.public_hostnames, local.tailnet_hostnames)

  cname_overrides = {
    "api-photos.${var.base_domain}" = "perun-1.tail6f3b0.ts.net"
  }

  unproxied_hostnames = local.tailnet_hostnames

  public_hostnames_sorted = sort(tolist(local.public_hostnames))
  all_hostnames_sorted    = sort(tolist(local.all_hostnames))
  tunnel_cname_target     = "${var.tunnel_id}.cfargotunnel.com"
}
