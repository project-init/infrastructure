#------------------------------------------------------------------------------
# Test Setup Module
# Exposes the CIDR calculation logic for unit testing without AWS resources
#------------------------------------------------------------------------------

variable "target_regions" {
  type = list(string)
}

variable "legacy_allocations" {
  type = list(object({
    name        = string
    cidr        = string
    description = string
  }))
  default = []
}

variable "shared_pool_cidr_override" {
  type    = string
  default = null
}

variable "external_pool_cidr_override" {
  type    = string
  default = null
}

locals {
  # Generate all sixteen /12 CIDRs from 10.0.0.0/8
  all_slash12_cidrs = [for i in range(16) : cidrsubnet("10.0.0.0/8", 4, i)]

  # Extract legacy CIDRs for comparison
  legacy_cidrs = [for alloc in var.legacy_allocations : alloc.cidr]

  # Determine if overrides are being used
  using_shared_override   = var.shared_pool_cidr_override != null
  using_external_override = var.external_pool_cidr_override != null

  # Validate overrides don't overlap with legacy allocations
  shared_override_overlaps_legacy   = local.using_shared_override && contains(local.legacy_cidrs, var.shared_pool_cidr_override)
  external_override_overlaps_legacy = local.using_external_override && contains(local.legacy_cidrs, var.external_pool_cidr_override)

  # Validate overrides are valid /12 blocks from our pool
  shared_override_in_pool   = local.using_shared_override && contains(local.all_slash12_cidrs, var.shared_pool_cidr_override)
  external_override_in_pool = local.using_external_override && contains(local.all_slash12_cidrs, var.external_pool_cidr_override)

  # Validate overrides don't overlap with each other
  overrides_overlap = (
    local.using_shared_override &&
    local.using_external_override &&
    var.shared_pool_cidr_override == var.external_pool_cidr_override
  )

  # CIDRs reserved by overrides (to exclude from available pool for regional allocation)
  override_cidrs = compact([
    local.using_shared_override ? var.shared_pool_cidr_override : null,
    local.using_external_override ? var.external_pool_cidr_override : null
  ])

  # Available CIDRs = all CIDRs minus legacy CIDRs minus override CIDRs
  available_cidrs = [
    for cidr in local.all_slash12_cidrs : cidr
    if !contains(local.legacy_cidrs, cidr) && !contains(local.override_cidrs, cidr)
  ]

  # When using overrides, we need fewer auto-allocated blocks
  auto_allocated_special_pools = (local.using_shared_override ? 0 : 1) + (local.using_external_override ? 0 : 1)

  # Capacity validation
  required_capacity = length(var.target_regions) + local.auto_allocated_special_pools
  total_available   = length(local.available_cidrs)

  # Bottom-Up: Assign target_regions to the LOWEST available CIDRs
  regional_pool_assignments = {
    for idx, region in var.target_regions :
    region => local.available_cidrs[idx]
    if idx < local.total_available - local.auto_allocated_special_pools
  }

  # Top-Down: External pool gets the HIGHEST available CIDR (or override)
  external_pool_cidr = local.using_external_override ? var.external_pool_cidr_override : (
    local.total_available > 0 ? local.available_cidrs[local.total_available - 1] : null
  )

  # Top-Down: Shared pool gets the SECOND HIGHEST available CIDR (or override)
  # When external is overridden but shared is not, shared gets the highest available
  shared_pool_cidr = local.using_shared_override ? var.shared_pool_cidr_override : (
    local.using_external_override ? (
      local.total_available > 0 ? local.available_cidrs[local.total_available - 1] : null
      ) : (
      local.total_available > 1 ? local.available_cidrs[local.total_available - 2] : null
    )
  )

  # Capacity check
  has_sufficient_capacity = local.required_capacity <= local.total_available

  # Validation flags for testing
  is_valid = (
    !local.shared_override_overlaps_legacy &&
    !local.external_override_overlaps_legacy &&
    (!local.using_shared_override || local.shared_override_in_pool) &&
    (!local.using_external_override || local.external_override_in_pool) &&
    !local.overrides_overlap &&
    local.has_sufficient_capacity
  )
}

output "all_slash12_cidrs" {
  description = "All 16 /12 CIDRs from 10.0.0.0/8"
  value       = local.all_slash12_cidrs
}

output "available_cidrs" {
  description = "Available CIDRs after excluding legacy allocations and overrides"
  value       = local.available_cidrs
}

output "regional_pool_assignments" {
  description = "Map of region to assigned CIDR"
  value       = local.regional_pool_assignments
}

output "shared_pool_cidr" {
  description = "CIDR assigned to shared pool"
  value       = local.shared_pool_cidr
}

output "external_pool_cidr" {
  description = "CIDR assigned to external pool"
  value       = local.external_pool_cidr
}

output "required_capacity" {
  description = "Number of /12 blocks required"
  value       = local.required_capacity
}

output "total_available" {
  description = "Number of /12 blocks available"
  value       = local.total_available
}

output "has_sufficient_capacity" {
  description = "Whether there is sufficient capacity"
  value       = local.has_sufficient_capacity
}

output "using_shared_override" {
  description = "Whether shared pool override is being used"
  value       = local.using_shared_override
}

output "using_external_override" {
  description = "Whether external pool override is being used"
  value       = local.using_external_override
}

output "shared_override_overlaps_legacy" {
  description = "Whether shared override overlaps with legacy"
  value       = local.shared_override_overlaps_legacy
}

output "external_override_overlaps_legacy" {
  description = "Whether external override overlaps with legacy"
  value       = local.external_override_overlaps_legacy
}

output "overrides_overlap" {
  description = "Whether shared and external overrides are the same"
  value       = local.overrides_overlap
}

output "is_valid" {
  description = "Whether the configuration is valid"
  value       = local.is_valid
}

output "auto_allocated_special_pools" {
  description = "Number of auto-allocated special pools (0, 1, or 2)"
  value       = local.auto_allocated_special_pools
}
