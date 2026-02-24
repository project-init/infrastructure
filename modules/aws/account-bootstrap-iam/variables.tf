variable "platform_account_id" {
  description = "The AWS Account ID of the Platform Account."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.platform_account_id))
    error_message = "platform_account_id must be a valid 12-digit AWS Account ID."
  }
}

variable "organization" {
  description = "The organization name (e.g., 'acme'). Used for tagging."
  type        = string
}

variable "namespace" {
  description = "The namespace for the account (e.g., 'core', 'analytics'). Used for tagging."
  type        = string
}

variable "environment" {
  description = "The environment. Must be one of: staging, production, global."
  type        = string

  validation {
    condition     = contains(["staging", "production", "global"], var.environment)
    error_message = "Environment must be one of: staging, production, global."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources."
  type        = map(string)
  default     = {}
}
