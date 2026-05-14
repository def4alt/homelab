variable "hcloud_token" {
  type        = string
  sensitive   = true
  description = "Hetzner Cloud API token."
}

variable "ssh_key_name" {
  type        = string
  description = "Name of the SSH key in Hetzner project to inject into the server."
}

variable "location" {
  type        = string
  default     = "fsn1"
  description = "Hetzner datacenter location."
}

variable "server_type" {
  type        = string
  default     = "cpx22"
  description = "Hetzner server type (cpx22 = 2 vCPU, 4 GB RAM, AMD)."
}

variable "server_name" {
  type        = string
  default     = "hermes-vps"
  description = "Hostname for the Hermes VM."
}

variable "volume_size_gb" {
  type        = number
  default     = 20
  description = "Size of the attached persistent volume (GB)."
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
  description = "IPv4/IPv6 CIDR ranges allowed to SSH into the VPS."
}
