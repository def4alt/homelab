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
    "projects.${var.base_domain}",
    "sea.${var.base_domain}",
    "tv.${var.base_domain}",
    "tv-plex.${var.base_domain}",
    var.base_domain,
  ])

  hetzner_public_hostnames = toset([
    "auth.${var.base_domain}",
    "papers.${var.base_domain}",
    "dashboard.${var.base_domain}",
    var.base_domain,
  ])

  minecraft_hostname   = "minecraft.${var.base_domain}"
  minecraft_tailnet_ip = "100.119.240.70"
  shell_hostname       = "shell.${var.base_domain}"

  tailnet_hostnames = toset([
    "api-photos.${var.base_domain}",
  ])

  all_hostnames = setunion(local.public_hostnames, local.tailnet_hostnames, toset([local.minecraft_hostname, local.shell_hostname]))

  cname_overrides = {
    "api-photos.${var.base_domain}" = "perun.tail6f3b0.ts.net"
  }

  unproxied_hostnames = local.tailnet_hostnames

  public_origin_by_hostname = {
    for hostname in local.public_hostnames : hostname => {
      service       = contains(local.hetzner_public_hostnames, hostname) ? "https://46.62.137.102:443" : var.tunnel_origin_url
      no_tls_verify = contains(local.hetzner_public_hostnames, hostname)
    }
  }

  public_hostnames_sorted = sort(tolist(local.public_hostnames))
  all_hostnames_sorted    = sort(tolist(local.all_hostnames))
  tunnel_cname_target     = "${var.tunnel_id}.cfargotunnel.com"
}
