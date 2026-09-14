variable "name" {
  description = "Complete bucket name supplied by the caller."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 3 && length(var.name) <= 63
    error_message = "name must contain between 3 and 63 characters."
  }
}

variable "context" {
  description = "Cloud Posse label context passed through to the bucket module."
  type        = any
  nullable    = false
}

variable "tags" {
  description = "Additional tags merged with the Cloud Posse label context."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "force_destroy" {
  description = "Whether Terraform may delete the bucket when it still contains objects."
  type        = bool
  default     = false
  nullable    = false
}

variable "versioning_enabled" {
  description = "Whether S3 object versioning is enabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "sse_algorithm" {
  description = "Server-side encryption algorithm used by the bucket."
  type        = string
  default     = "AES256"
  nullable    = false

  validation {
    condition     = contains(["AES256", "aws:kms"], var.sse_algorithm)
    error_message = "sse_algorithm must be AES256 or aws:kms."
  }
}

variable "kms_master_key_arn" {
  description = "KMS key ARN used when sse_algorithm is aws:kms. An empty value uses the AWS-managed S3 key."
  type        = string
  default     = ""
  nullable    = false
}

variable "blocked_encryption_types" {
  description = "Encryption types blocked by the bucket encryption configuration."
  type        = list(string)
  default     = ["NONE"]
  nullable    = false
}

variable "allow_ssl_requests_only" {
  description = "Whether the bucket policy denies requests that do not use HTTPS."
  type        = bool
  default     = true
  nullable    = false
}

variable "s3_object_ownership" {
  description = "S3 object ownership mode for the bucket."
  type        = string
  default     = "BucketOwnerEnforced"
  nullable    = false

  validation {
    condition     = contains(["ObjectWriter", "BucketOwnerPreferred", "BucketOwnerEnforced"], var.s3_object_ownership)
    error_message = "s3_object_ownership must be ObjectWriter, BucketOwnerPreferred, or BucketOwnerEnforced."
  }
}

variable "block_public_acls" {
  description = "Whether S3 blocks new public ACLs on the bucket."
  type        = bool
  default     = true
  nullable    = false
}

variable "block_public_policy" {
  description = "Whether S3 blocks new public bucket policies."
  type        = bool
  default     = true
  nullable    = false
}

variable "ignore_public_acls" {
  description = "Whether S3 ignores public ACLs on the bucket."
  type        = bool
  default     = true
  nullable    = false
}

variable "restrict_public_buckets" {
  description = "Whether S3 restricts public bucket policies."
  type        = bool
  default     = true
  nullable    = false
}

variable "lifecycle_rules" {
  description = "Enabled prefix-based lifecycle rules. Retention choices belong to the caller."
  type = list(object({
    id                                     = string
    prefix                                 = string
    expiration_days                        = number
    noncurrent_expiration_days             = number
    abort_incomplete_multipart_upload_days = number
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules :
      try(length(trimspace(rule.id)) > 0 && length(rule.id) <= 255, false)
    ])
    error_message = "Each lifecycle rule ID must contain 1-255 characters and must not be blank."
  }

  validation {
    condition = length(var.lifecycle_rules) == length(distinct([
      for rule in var.lifecycle_rules : rule.id
    ]))
    error_message = "Lifecycle rule IDs must be unique."
  }

  validation {
    condition = alltrue([
      for rule in var.lifecycle_rules : rule.prefix != null
    ])
    error_message = "Lifecycle rule prefixes must not be null. Use an empty string to match all objects."
  }

  validation {
    condition = alltrue(flatten([
      for rule in var.lifecycle_rules : [
        for days in [
          rule.expiration_days,
          rule.noncurrent_expiration_days,
          rule.abort_incomplete_multipart_upload_days,
        ] : try(days > 0 && floor(days) == days, false)
      ]
    ]))
    error_message = "Lifecycle expiration and multipart-abort days must be positive integers."
  }
}
