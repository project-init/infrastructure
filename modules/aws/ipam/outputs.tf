output "ipam_id" {
  description = "ID of the created IPAM."
  value       = aws_vpc_ipam.this.id
}

output "ipam_arn" {
  description = "ARN of the created IPAM."
  value       = aws_vpc_ipam.this.arn
}

output "ipam_scope_id" {
  description = "ID of the private default scope."
  value       = aws_vpc_ipam.this.private_default_scope_id
}

output "global_pool_id" {
  description = "ID of the top-level 10.0.0.0/8 global pool."
  value       = aws_vpc_ipam_pool.global.id
}

output "global_pool_arn" {
  description = "ARN of the global pool."
  value       = aws_vpc_ipam_pool.global.arn
}

output "regional_pools" {
  description = "Map of region to pool details for the /12 regional pools."
  value = {
    for region, pool in aws_vpc_ipam_pool.regional : region => {
      pool_id  = pool.id
      pool_arn = pool.arn
      cidr     = aws_vpc_ipam_pool_cidr.regional[region].cidr
    }
  }
}

output "regional_pool_ids" {
  description = "Map of region to pool ID for the /12 regional pools."
  value       = { for region, pool in aws_vpc_ipam_pool.regional : region => pool.id }
}

output "shared_pool_id" {
  description = "ID of the /12 pool reserved for Shared VPCs."
  value       = aws_vpc_ipam_pool.shared.id
}

output "shared_pool_arn" {
  description = "ARN of the shared pool."
  value       = aws_vpc_ipam_pool.shared.arn
}

output "shared_pool_cidr" {
  description = "CIDR block assigned to the shared pool."
  value       = local.shared_pool_cidr
}

output "external_pool_id" {
  description = "ID of the /12 pool reserved for External Integrations."
  value       = aws_vpc_ipam_pool.external.id
}

output "external_pool_arn" {
  description = "ARN of the external pool."
  value       = aws_vpc_ipam_pool.external.arn
}

output "external_pool_cidr" {
  description = "CIDR block assigned to the external pool."
  value       = local.external_pool_cidr
}

output "allocation_summary" {
  description = "Summary of all CIDR allocations for documentation purposes."
  value = {
    global_cidr = "10.0.0.0/8"
    regional_allocations = {
      for region, pool in aws_vpc_ipam_pool.regional : region => aws_vpc_ipam_pool_cidr.regional[region].cidr
    }
    shared_cidr   = local.shared_pool_cidr
    external_cidr = local.external_pool_cidr
    legacy_reservations = {
      for alloc in var.legacy_allocations : alloc.name => alloc.cidr
    }
    available_capacity = local.total_available - local.required_capacity
  }
}
