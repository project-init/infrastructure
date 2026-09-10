module "bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.12.0"

  bucket_name = var.name
  context     = var.context
  tags        = var.tags

  force_destroy            = var.force_destroy
  versioning_enabled       = var.versioning_enabled
  sse_algorithm            = var.sse_algorithm
  kms_master_key_arn       = var.kms_master_key_arn
  blocked_encryption_types = var.blocked_encryption_types
  allow_ssl_requests_only  = var.allow_ssl_requests_only
  s3_object_ownership      = var.s3_object_ownership
  block_public_acls        = var.block_public_acls
  block_public_policy      = var.block_public_policy
  ignore_public_acls       = var.ignore_public_acls
  restrict_public_buckets  = var.restrict_public_buckets
  user_enabled             = false

  lifecycle_configuration_rules = [
    for rule in var.lifecycle_rules : {
      id      = rule.id
      enabled = true

      filter_and = {
        prefix = rule.prefix
      }

      expiration = {
        days = rule.expiration_days
      }

      noncurrent_version_expiration = {
        noncurrent_days = rule.noncurrent_expiration_days
      }

      abort_incomplete_multipart_upload_days = rule.abort_incomplete_multipart_upload_days
    }
  ]
}
