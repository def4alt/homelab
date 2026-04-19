locals {
  aws_backup_bucket_arn  = "arn:aws:s3:::${var.aws_backup_bucket_name}"
  aws_backup_objects_arn = "arn:aws:s3:::${var.aws_backup_bucket_name}/${var.aws_backup_prefix}/*"
  b2_s3_endpoint_url     = "https://s3.${var.b2_s3_region}.backblazeb2.com"
}

moved {
  from = aws_s3_bucket.immich_backups
  to   = aws_s3_bucket.homelab_backups
}

moved {
  from = aws_s3_bucket_public_access_block.immich_backups
  to   = aws_s3_bucket_public_access_block.homelab_backups
}

moved {
  from = aws_s3_bucket_versioning.immich_backups
  to   = aws_s3_bucket_versioning.homelab_backups
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.immich_backups
  to   = aws_s3_bucket_server_side_encryption_configuration.homelab_backups
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.immich_backups
  to   = aws_s3_bucket_lifecycle_configuration.homelab_backups
}

resource "aws_s3_bucket" "homelab_backups" {
  bucket        = var.aws_backup_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "homelab_backups" {
  bucket = aws_s3_bucket.homelab_backups.id

  rule {
    id     = "def4alt-homelab-backups-to-deep-archive"
    status = "Enabled"

    filter {
      prefix = "${var.aws_backup_prefix}/"
    }

    transition {
      days          = var.aws_transition_days
      storage_class = "DEEP_ARCHIVE"
    }

    expiration {
      days = var.aws_expiration_days
    }
  }
}

data "aws_iam_policy_document" "immich_backup" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [local.aws_backup_bucket_arn]
  }

  statement {
    sid    = "BackupObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = [local.aws_backup_objects_arn]
  }
}

resource "aws_iam_user" "immich_backup" {
  name = "immich-backup"
}

resource "aws_iam_user_policy" "immich_backup" {
  name   = "immich-backup"
  user   = aws_iam_user.immich_backup.name
  policy = data.aws_iam_policy_document.immich_backup.json
}

resource "aws_iam_access_key" "immich_backup" {
  user = aws_iam_user.immich_backup.name
}

resource "b2_bucket" "immich_library" {
  bucket_name = var.b2_bucket_name
  bucket_type = "allPrivate"
}

resource "b2_application_key" "immich_library" {
  key_name = var.b2_key_name
  capabilities = [
    "deleteFiles",
    "listBuckets",
    "listFiles",
    "readFiles",
    "writeFiles",
  ]
  bucket_id = b2_bucket.immich_library.bucket_id
}
