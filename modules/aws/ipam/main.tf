#------------------------------------------------------------------------------
# IPAM Module
# Manages the top-level IP Address Management (IPAM) within the Platform Account.
# Subdivides 10.0.0.0/8 into regional /12 pools with bottom-up allocation for
# regions and top-down allocation for shared/external pools.
#------------------------------------------------------------------------------

data "aws_region" "current" {}

#------------------------------------------------------------------------------
# Local Variables - CIDR Math and Allocation Logic
#------------------------------------------------------------------------------
locals {
  # Generate all sixteen /12 CIDRs from 10.0.0.0/8
  # cidrsubnet("10.0.0.0/8", 4, n) produces /12 blocks
  # n=0 -> 10.0.0.0/12, n=1 -> 10.16.0.0/12, ..., n=15 -> 10.240.0.0/12
  all_slash12_cidrs = [for i in range(16) : cidrsubnet("10.0.0.0/8", 4, i)]

  # Extract legacy CIDRs for comparison
  legacy_cidrs = [for alloc in var.legacy_allocations : alloc.cidr]

  # Determine if overrides are being used
  using_shared_override   = var.shared_pool_cidr_override != null
  using_external_override = var.external_pool_cidr_override != null

  # Validate overrides don't overlap with legacy allocations (computed for precondition)
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

  # Operating regions = union of target_regions and current region
  # Note: data.aws_region.current.id returns the region name (e.g., "us-east-1")
  operating_regions = distinct(concat(var.target_regions, [data.aws_region.current.id]))

  # Bottom-Up: Assign target_regions to the LOWEST available CIDRs
  # Example: If available_cidrs = [10.0.0.0/12, 10.16.0.0/12, 10.32.0.0/12, ...]
  # and target_regions = ["us-east-1", "us-west-2"]
  # then us-east-1 -> 10.0.0.0/12, us-west-2 -> 10.16.0.0/12
  regional_pool_assignments = {
    for idx, region in var.target_regions :
    region => local.available_cidrs[idx]
    if idx < local.total_available - local.auto_allocated_special_pools
  }

  # Top-Down: External pool gets the HIGHEST available CIDR (or override)
  external_pool_cidr = local.using_external_override ? var.external_pool_cidr_override : local.available_cidrs[local.total_available - 1]

  # Top-Down: Shared pool gets the SECOND HIGHEST available CIDR (or override)
  # When external is overridden but shared is not, shared gets the highest available
  shared_pool_cidr = local.using_shared_override ? var.shared_pool_cidr_override : (
    local.using_external_override ? local.available_cidrs[local.total_available - 1] : local.available_cidrs[local.total_available - 2]
  )

  # Common tags for all resources
  common_tags = merge(
    {
      Module  = "ipam"
      Purpose = "IP Address Management"
    },
    var.tags
  )
}

#------------------------------------------------------------------------------
# Capacity and Override Validation
#------------------------------------------------------------------------------
resource "terraform_data" "validation" {
  lifecycle {
    # Validate shared override doesn't overlap with legacy
    precondition {
      condition     = !local.shared_override_overlaps_legacy
      error_message = "shared_pool_cidr_override '${coalesce(var.shared_pool_cidr_override, "null")}' overlaps with a legacy allocation. Legacy CIDRs: ${jsonencode(local.legacy_cidrs)}"
    }

    # Validate external override doesn't overlap with legacy
    precondition {
      condition     = !local.external_override_overlaps_legacy
      error_message = "external_pool_cidr_override '${coalesce(var.external_pool_cidr_override, "null")}' overlaps with a legacy allocation. Legacy CIDRs: ${jsonencode(local.legacy_cidrs)}"
    }

    # Validate shared override is a valid /12 from our pool
    precondition {
      condition     = !local.using_shared_override || local.shared_override_in_pool
      error_message = "shared_pool_cidr_override '${coalesce(var.shared_pool_cidr_override, "null")}' is not a valid /12 block within 10.0.0.0/8. Valid blocks: ${jsonencode(local.all_slash12_cidrs)}"
    }

    # Validate external override is a valid /12 from our pool
    precondition {
      condition     = !local.using_external_override || local.external_override_in_pool
      error_message = "external_pool_cidr_override '${coalesce(var.external_pool_cidr_override, "null")}' is not a valid /12 block within 10.0.0.0/8. Valid blocks: ${jsonencode(local.all_slash12_cidrs)}"
    }

    # Validate overrides don't overlap with each other
    precondition {
      condition     = !local.overrides_overlap
      error_message = "shared_pool_cidr_override and external_pool_cidr_override cannot be the same CIDR block."
    }

    # Validate capacity
    precondition {
      condition     = local.required_capacity <= local.total_available
      error_message = "Insufficient IPAM capacity. Required: ${local.required_capacity} /12 blocks (${length(var.target_regions)} regions + ${local.auto_allocated_special_pools} auto-allocated). Available: ${local.total_available} blocks after ${length(local.legacy_cidrs)} legacy reservations and ${length(local.override_cidrs)} override reservations."
    }
  }
}

#------------------------------------------------------------------------------
# IPAM Resource
#------------------------------------------------------------------------------
resource "aws_vpc_ipam" "this" {
  description = "Platform IPAM for centralized IP address management"

  dynamic "operating_regions" {
    for_each = toset(local.operating_regions)
    content {
      region_name = operating_regions.value
    }
  }

  tags = merge(local.common_tags, {
    Name = "platform-ipam"
  })
}

#------------------------------------------------------------------------------
# Global Pool (10.0.0.0/8)
#------------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "global" {
  address_family                    = "ipv4"
  ipam_scope_id                     = aws_vpc_ipam.this.private_default_scope_id
  description                       = "Global pool for all platform IP allocations"
  publicly_advertisable             = false
  auto_import                       = false
  allocation_default_netmask_length = 12

  tags = merge(local.common_tags, {
    Name = "global-pool"
    Tier = "global"
  })
}

resource "aws_vpc_ipam_pool_cidr" "global" {
  ipam_pool_id = aws_vpc_ipam_pool.global.id
  cidr         = "10.0.0.0/8"
}

#------------------------------------------------------------------------------
# Legacy Reservations
# Mark legacy CIDRs as allocated to prevent IPAM from using them
#------------------------------------------------------------------------------
resource "aws_vpc_ipam_pool_cidr_allocation" "legacy" {
  for_each = { for alloc in var.legacy_allocations : alloc.name => alloc }

  ipam_pool_id = aws_vpc_ipam_pool.global.id
  cidr         = each.value.cidr
  description  = "Reserved for legacy network: ${each.value.name} - ${each.value.description}"

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

#------------------------------------------------------------------------------
# Regional Pools (Bottom-Up Allocation)
# Each region gets a /12 from the lowest available CIDRs
#------------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "regional" {
  for_each = local.regional_pool_assignments

  address_family                    = "ipv4"
  ipam_scope_id                     = aws_vpc_ipam.this.private_default_scope_id
  locale                            = each.key
  source_ipam_pool_id               = aws_vpc_ipam_pool.global.id
  description                       = "Regional pool for ${each.key}"
  auto_import                       = false
  allocation_default_netmask_length = 16 # VPCs typically get /16

  tags = merge(local.common_tags, {
    Name   = "regional-pool-${each.key}"
    Tier   = "regional"
    Region = each.key
  })

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

resource "aws_vpc_ipam_pool_cidr" "regional" {
  for_each = local.regional_pool_assignments

  ipam_pool_id = aws_vpc_ipam_pool.regional[each.key].id
  cidr         = each.value

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

#------------------------------------------------------------------------------
# Shared Pool (Top-Down Allocation)
# Reserved for Shared VPCs across all regions
#------------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "shared" {
  address_family                    = "ipv4"
  ipam_scope_id                     = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id               = aws_vpc_ipam_pool.global.id
  description                       = "Shared pool for Shared VPCs"
  auto_import                       = false
  allocation_default_netmask_length = 15 # Shared VPCs get /15

  tags = merge(local.common_tags, {
    Name = "shared-pool"
    Tier = "shared"
  })

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

resource "aws_vpc_ipam_pool_cidr" "shared" {
  ipam_pool_id = aws_vpc_ipam_pool.shared.id
  cidr         = local.shared_pool_cidr

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

#------------------------------------------------------------------------------
# External Pool (Top-Down Allocation)
# Reserved for external integrations (VPN, Direct Connect, Partner networks)
#------------------------------------------------------------------------------
resource "aws_vpc_ipam_pool" "external" {
  address_family                    = "ipv4"
  ipam_scope_id                     = aws_vpc_ipam.this.private_default_scope_id
  source_ipam_pool_id               = aws_vpc_ipam_pool.global.id
  description                       = "External pool for integrations"
  auto_import                       = false
  allocation_default_netmask_length = 16

  tags = merge(local.common_tags, {
    Name = "external-pool"
    Tier = "external"
  })

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}

resource "aws_vpc_ipam_pool_cidr" "external" {
  ipam_pool_id = aws_vpc_ipam_pool.external.id
  cidr         = local.external_pool_cidr

  depends_on = [aws_vpc_ipam_pool_cidr.global]
}
