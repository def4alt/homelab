terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.45.0"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

data "hcloud_ssh_key" "default" {
  name = var.ssh_key_name
}

# ── Server ──────────────────────────────────────────────────────────

resource "hcloud_server" "hermes" {
  name        = var.server_name
  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.location
  ssh_keys    = [data.hcloud_ssh_key.default.id]
  user_data   = file("${path.module}/cloud-init.yaml")

  public_net {
    ipv4_enabled = true
    ipv6_enabled = true
  }
}

# ── Persistent volume ───────────────────────────────────────────────

resource "hcloud_volume" "hermes_data" {
  name      = "${var.server_name}-data"
  size      = var.volume_size_gb
  server_id = hcloud_server.hermes.id
  automount = true
  format    = "ext4"
}

# ── Firewall ───────────────────────────────────────────────────────

resource "hcloud_firewall" "hermes" {
  name = "${var.server_name}-firewall"

  rule {
    direction = "in"
    protocol  = "tcp"
    source_ips = var.allowed_ssh_cidrs
    port      = "22"
    description = "SSH"
  }
}

resource "hcloud_firewall_attachment" "hermes" {
  firewall_id = hcloud_firewall.hermes.id
  server_ids  = [hcloud_server.hermes.id]
}
