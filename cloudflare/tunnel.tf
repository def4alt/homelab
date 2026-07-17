resource "cloudflare_zero_trust_tunnel_cloudflared_config" "homelab" {
  count = var.manage_tunnel_config ? 1 : 0

  account_id = var.account_id
  tunnel_id  = var.tunnel_id

  config {
    ingress_rule {
      hostname = local.shell_hostname
      service  = "ssh://shell.shell.svc.cluster.local:22"
    }

    dynamic "ingress_rule" {
      for_each = local.public_hostnames_sorted
      content {
        hostname = ingress_rule.value
        service  = local.public_origin_by_hostname[ingress_rule.value].service

        origin_request {
          http_host_header   = ingress_rule.value
          origin_server_name = ingress_rule.value
          no_tls_verify      = local.public_origin_by_hostname[ingress_rule.value].no_tls_verify
        }
      }
    }

    ingress_rule {
      service = "http_status:404"
    }
  }
}
