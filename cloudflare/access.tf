resource "cloudflare_zero_trust_access_application" "app" {
  for_each = local.hostnames

  zone_id          = var.zone_id
  name             = "homelab-${each.key}"
  domain           = each.key
  type             = "self_hosted"
  session_duration = var.session_duration
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  for_each = local.hostnames

  zone_id        = var.zone_id
  application_id = cloudflare_zero_trust_access_application.app[each.key].id
  name           = "allow-allowed-emails"
  precedence     = 1
  decision       = "allow"

  include {
    email = var.allowed_emails
  }
}

resource "cloudflare_zero_trust_access_policy" "deny_all" {
  for_each = local.hostnames

  zone_id        = var.zone_id
  application_id = cloudflare_zero_trust_access_application.app[each.key].id
  name           = "deny-everyone-else"
  precedence     = 2
  decision       = "deny"

  include {
    everyone = true
  }
}
