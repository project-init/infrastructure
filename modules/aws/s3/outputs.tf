output "bucket_id" {
  description = "Bucket name."
  value       = module.bucket.bucket_id
}

output "bucket_arn" {
  description = "Bucket ARN."
  value       = module.bucket.bucket_arn
}

output "env_variables" {
  description = "Environment variables containing S3_BUCKET for the bucket."
  value = [
    {
      name  = "S3_BUCKET"
      value = module.bucket.bucket_id
    }
  ]
}
