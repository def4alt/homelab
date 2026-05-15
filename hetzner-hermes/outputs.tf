output "server_ipv4" {
  value       = hcloud_server.hermes.ipv4_address
  description = "Public IPv4 address of the Hermes VPS."
}

output "server_ipv6" {
  value       = hcloud_server.hermes.ipv6_address
  description = "Public IPv6 address of the Hermes VPS."
}

output "server_name" {
  value       = hcloud_server.hermes.name
  description = "Server hostname."
}

output "volume_id" {
  value       = hcloud_volume.hermes_data.id
  description = "ID of the attached persistent volume."
}

output "ssh_command" {
  value       = "ssh root@${hcloud_server.hermes.ipv4_address}"
  description = "Quick SSH command to access the VPS over IPv4."
}
