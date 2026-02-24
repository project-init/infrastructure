variable "organization" {
  description = "The organization name (e.g., 'acme', 'mycompany'). Used for tagging."
  type        = string
}

variable "namespace" {
  description = "The namespace for the account (e.g., 'core', 'analytics'). Part of the account name."
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

variable "email" {
  description = "Root email address for the new account."
  type        = string
}

variable "role_name" {
  description = "The name of the IAM role to create in the new account for initial access."
  type        = string
  default     = "management-admin"
}

variable "parent_id" {
  description = "Parent Organizational Unit ID or Root ID."
  type        = string
  default     = null
}

variable "tags" {
  description = "Additional tags to apply."
  type        = map(string)
  default     = {}
}
