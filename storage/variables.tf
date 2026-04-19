variable "aws_region" {
  description = "AWS region for the CNPG backup bucket."
  type        = string
  default     = "eu-west-1"
}

variable "aws_backup_bucket_name" {
  description = "Name of the S3 bucket that stores homelab CNPG backups."
  type        = string
  default     = "def4alt-homelab-backups"
}

variable "aws_backup_prefix" {
  description = "Prefix under the backup bucket used by CNPG/Barman."
  type        = string
  default     = "cnpg"
}

variable "aws_transition_days" {
  description = "Days before transitioning backup objects to Glacier Deep Archive."
  type        = number
  default     = 1
}

variable "aws_expiration_days" {
  description = "Days before expiring backup objects from the bucket."
  type        = number
  default     = 181
}

variable "b2_bucket_name" {
  description = "Backblaze B2 bucket for the Immich media library."
  type        = string
  default     = "def4alt-homelab-immich-library"
}

variable "b2_key_name" {
  description = "Human-friendly name for the restricted B2 application key."
  type        = string
  default     = "immich-library"
}

variable "b2_s3_region" {
  description = "Backblaze B2 S3 region string used by JuiceFS and Kubernetes secrets."
  type        = string
  default     = "eu-central-003"
}
