variable "root_domain" {
  description = "The root domain name (e.g., 'example.com')."
  type        = string

  validation {
    condition     = var.root_domain == lower(var.root_domain)
    error_message = "root_domain must be lowercase (DNS is case-insensitive, but we enforce lowercase for consistency)."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.root_domain))
    error_message = "root_domain must be a valid domain name (e.g., 'example.com'). It cannot start with a dot or contain invalid characters."
  }

  validation {
    condition     = !startswith(var.root_domain, ".")
    error_message = "root_domain cannot start with a dot."
  }

  validation {
    condition     = !endswith(var.root_domain, ".")
    error_message = "root_domain cannot end with a dot (FQDN format not expected)."
  }
}

variable "environments" {
  description = "List of environments to create subdomains for (e.g., ['staging', 'production'])."
  type        = list(string)
  default     = ["staging", "production"]

  validation {
    condition     = length(var.environments) > 0
    error_message = "At least one environment must be specified."
  }

  validation {
    condition = alltrue([
      for env in var.environments :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", env))
    ])
    error_message = "Each environment must be a valid subdomain label (lowercase alphanumeric, may contain hyphens but not at start/end)."
  }

  validation {
    condition = alltrue([
      for env in var.environments :
      length(env) <= 63
    ])
    error_message = "Each environment name must be 63 characters or fewer (DNS label limit)."
  }

  validation {
    condition     = length(var.environments) == length(distinct(var.environments))
    error_message = "Environment names must be unique."
  }
}

variable "tags" {
  description = "Tags to apply to all Hosted Zones."
  type        = map(string)
  default     = {}
}
