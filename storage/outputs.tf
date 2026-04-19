output "aws_backup_bucket_name" {
  value = aws_s3_bucket.homelab_backups.bucket
}

output "aws_backup_bucket_arn" {
  value = aws_s3_bucket.homelab_backups.arn
}

output "aws_backup_destination_path" {
  value = "s3://${aws_s3_bucket.homelab_backups.bucket}/${var.aws_backup_prefix}"
}

output "aws_backup_region" {
  value = var.aws_region
}

output "aws_backup_access_key_id" {
  value = aws_iam_access_key.immich_backup.id
}

output "aws_backup_secret_access_key" {
  value     = aws_iam_access_key.immich_backup.secret
  sensitive = true
}

output "b2_bucket_name" {
  value = b2_bucket.immich_library.bucket_name
}

output "b2_bucket_id" {
  value = b2_bucket.immich_library.bucket_id
}

output "b2_application_key_id" {
  value = b2_application_key.immich_library.application_key_id
}

output "b2_application_key" {
  value     = b2_application_key.immich_library.application_key
  sensitive = true
}

output "b2_s3_endpoint_url" {
  value = local.b2_s3_endpoint_url
}
