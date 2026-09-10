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