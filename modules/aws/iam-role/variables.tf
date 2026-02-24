variable "name" {
  description = "Name of the IAM role"
  type        = string
}

variable "description" {
  description = "Human-readable description of the role's purpose"
  type        = string
}

variable "assume_role_policy" {
  description = "JSON trust policy document. Required if is_instance_role = false"
  type        = string
  default     = null
}

variable "is_instance_role" {
  description = "When true, creates an instance profile and defaults trust policy to EC2 service"
  type        = bool
  default     = false
}

variable "inline_policies" {
  description = "List of inline policies to attach to the role"
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

variable "managed_policy_arns" {
  description = "List of managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "permission_boundary_name" {
  description = "Name of the permission boundary policy to look up and attach"
  type        = string
  default     = "default-permission-boundary"
}

variable "max_session_duration" {
  description = "Maximum session duration in seconds (3600-43200)"
  type        = number
  default     = 3600
}

variable "path" {
  description = "IAM path for the role"
  type        = string
  default     = "/"
}

variable "force_detach_policies" {
  description = "Whether to force detach policies before destroying the role"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags to apply to the role"
  type        = map(string)
  default     = {}
}
