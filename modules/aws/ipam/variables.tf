variable "target_regions" {
  description = "List of AWS Regions to provision regional IPAM pools for (e.g., ['us-east-1', 'us-west-2'])."
  type        = list(string)

  validation {
    condition     = length(var.target_regions) > 0
    error_message = "At least one target region must be specified."
  }
}

variable "legacy_allocations" {
  description = "List of /12 CIDRs to reserve/skip for legacy networks. These blocks will be excluded from allocation."
  type = list(object({
    name        = string
    cidr        = string
    description = string
  }))
  default = []

  validation {
    condition = alltrue([
      for alloc in var.legacy_allocations :
      can(cidrhost(alloc.cidr, 0)) && endswith(alloc.cidr, "/12")
    ])
    error_message = "All legacy allocations must be valid /12 CIDR blocks."
  }
}

variable "shared_pool_cidr_override" {
  description = "Optional override for the shared pool CIDR. Must be a valid /12 block within 10.0.0.0/8 and must not overlap with legacy_allocations."
  type        = string
  default     = null

  validation {
    condition = var.shared_pool_cidr_override == null || (
      can(cidrhost(var.shared_pool_cidr_override, 0)) &&
      endswith(var.shared_pool_cidr_override, "/12") &&
      can(regex("^10\\.", var.shared_pool_cidr_override))
    )
    error_message = "shared_pool_cidr_override must be a valid /12 CIDR block within 10.0.0.0/8 (e.g., '10.224.0.0/12')."
  }
}

variable "external_pool_cidr_override" {
  description = "Optional override for the external pool CIDR. Must be a valid /12 block within 10.0.0.0/8 and must not overlap with legacy_allocations."
  type        = string
  default     = null

  validation {
    condition = var.external_pool_cidr_override == null || (
      can(cidrhost(var.external_pool_cidr_override, 0)) &&
      endswith(var.external_pool_cidr_override, "/12") &&
      can(regex("^10\\.", var.external_pool_cidr_override))
    )
    error_message = "external_pool_cidr_override must be a valid /12 CIDR block within 10.0.0.0/8 (e.g., '10.240.0.0/12')."
  }
}

variable "tags" {
  description = "Tags to apply to all IPAM resources."
  type        = map(string)
  default     = {}
}
