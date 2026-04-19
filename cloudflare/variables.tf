variable "account_id" {
  description = "Cloudflare account ID."
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token; if unset, the provider uses CLOUDFLARE_API_TOKEN from the environment."
  type        = string
  sensitive   = true
  default     = null
}

variable "zone_id" {
  description = "Cloudflare zone ID that hosts the public DNS records."
  type        = string
}

variable "tunnel_id" {
  description = "Cloudflare Tunnel UUID (the tunnel backing cloudflared token mode)."
  type        = string
}

variable "base_domain" {
  description = "Base domain for homelab hostnames, e.g. def4alt.com."
  type        = string
}

variable "manage_tunnel_config" {
  description = "If true, manage cloudflare_tunnel_config ingress rules for hostnames in locals.tf."
  type        = bool
  default     = false
}

variable "manage_dns" {
  description = "If true, manage DNS records for hostnames in locals.tf."
  type        = bool
  default     = false
}

variable "tunnel_origin_url" {
  description = "Origin URL cloudflared should reach inside the cluster (Traefik)."
  type        = string
  default     = "https://traefik.infra.svc.cluster.local:443"
}
