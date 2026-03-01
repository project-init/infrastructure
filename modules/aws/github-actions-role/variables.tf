variable "name" {
  description = "Exact name for the IAM role. Conflicts with name_prefix."
  type        = string
  default     = null

  validation {
    condition     = (var.name == null) != (var.name_prefix == null)
    error_message = "Exactly one of name or name_prefix must be provided."
  }
}

variable "name_prefix" {
  description = "Prefix for the IAM role name. Conflicts with name."
  type        = string
  default     = null
}

variable "description" {
  description = "Description of the IAM role."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider. If not provided, it defaults to the default AWS provider ARN."
  type        = string
  default     = ""
}

variable "authorization_patterns" {
  description = "List of authorization patterns to configure the trust policy."
  type = list(object({
    sid = string
    claims = object({
      repositories      = list(string)
      repository_owners = optional(list(string))
      refs              = optional(list(string))
      environments      = optional(list(string))
      job_workflow_refs = optional(list(string))
    })
  }))
}

variable "inline_policies" {
  description = "List of inline policies to attach to the role."
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

variable "managed_policy_arns" {
  description = "List of IAM managed policy ARNs to attach to the role."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to the IAM role."
  type        = map(string)
  default     = {}
}
