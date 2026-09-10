module "bucket" {
  source  = "cloudposse/s3-bucket/aws"
  version = "4.12.0"

  bucket_name = var.name
  context     = var.context
  tags        = var.tags

  force_destroy            = false
  versioning_enabled       = true
  sse_algorithm            = "AES256"
  blocked_encryption_types = ["NONE"]
  allow_ssl_requests_only  = true
  s3_object_ownership      = "BucketOwnerEnforced"
  block_public_acls        = true
  block_public_policy      = true
  ignore_public_acls       = true
  restrict_public_buckets  = true
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