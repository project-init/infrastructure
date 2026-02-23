variable "allowed_principals" {
  description = "List of ARNs (SSO Roles or Users) allowed to assume these roles."
  type        = list(string)
}

variable "tags" {
  description = "Additional tags to apply."
  type        = map(string)
  default     = {}
}
