# AWS IPAM Module

This module manages the top-level IP Address Management (IPAM) within the Platform Account.

## Overview

The module is responsible for:
- Creating the centralized IPAM resource with multi-region support
- Provisioning the global `10.0.0.0/8` pool
- Subdividing into regional `/12` pools using **bottom-up** allocation
- Creating dedicated `/12` pools for **Shared VPCs** and **External Integrations** using **top-down** allocation
- Reserving legacy CIDR blocks to prevent allocation conflicts

## Prerequisites

- Must be executed with credentials from the **Platform Account**
- AWS IPAM service must be available in the target regions

## Architecture

```
10.0.0.0/8 (Global Pool)
├── 10.0.0.0/12   ─► Regional Pool: us-east-1 (Bottom-Up)
├── 10.16.0.0/12  ─► Regional Pool: us-west-2 (Bottom-Up)
├── 10.32.0.0/12  ─► Regional Pool: eu-west-1 (Bottom-Up)
├── ...
├── 10.208.0.0/12 ─► [Available for future regions]
├── 10.224.0.0/12 ─► Shared Pool (Top-Down, 2nd highest)
└── 10.240.0.0/12 ─► External Pool (Top-Down, highest)
```

### Allocation Strategy

| Pool Type | Strategy | Description |
|-----------|----------|-------------|
| Regional | Bottom-Up | Regions are assigned `/12` blocks starting from the lowest available CIDR |
| Shared | Top-Down | Reserved for Shared VPCs, allocated from the second-highest available block |
| External | Top-Down | Reserved for external integrations (VPN, Direct Connect), allocated from the highest available block |
| Legacy | Reserved | Pre-existing network ranges that must be skipped |

## Usage

### Basic Usage (Auto-Allocation)

```hcl
module "ipam" {
  source = "./modules/ipam"

  target_regions = ["us-east-1", "us-west-2", "eu-west-1"]

  legacy_allocations = [
    {
      name        = "datacenter-east"
      cidr        = "10.48.0.0/12"
      description = "On-premises datacenter in US East"
    },
    {
      name        = "acquired-company"
      cidr        = "10.64.0.0/12"
      description = "Network from acquired subsidiary"
    }
  ]

  tags = {
    Team    = "Platform"
    Project = "Networking"
  }
}
```

### With CIDR Overrides

Use overrides when you need specific CIDR blocks for shared or external pools:

```hcl
module "ipam" {
  source = "./modules/ipam"

  target_regions = ["us-east-1", "us-west-2"]

  # Override the default top-down allocation
  shared_pool_cidr_override   = "10.128.0.0/12"
  external_pool_cidr_override = "10.144.0.0/12"

  tags = {
    Team = "Platform"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `target_regions` | `list(string)` | - | Yes | List of AWS Regions to provision regional IPAM pools for. |
| `legacy_allocations` | `list(object)` | `[]` | No | List of `/12` CIDRs to reserve for legacy networks. |
| `shared_pool_cidr_override` | `string` | `null` | No | Override for the shared pool CIDR. Must be a valid `/12` block. |
| `external_pool_cidr_override` | `string` | `null` | No | Override for the external pool CIDR. Must be a valid `/12` block. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to all IPAM resources. |

### `legacy_allocations` Object Structure

```hcl
{
  name        = string  # Identifier for the legacy network
  cidr        = string  # Must be a /12 CIDR block
  description = string  # Description of the legacy network
}
```

### CIDR Override Rules

When using `shared_pool_cidr_override` or `external_pool_cidr_override`:

- Must be a valid `/12` CIDR block within `10.0.0.0/8`
- Must not overlap with any `legacy_allocations`
- Must not be the same as each other
- Override CIDRs are excluded from the available pool for regional allocation

## Outputs

| Name | Description |
|------|-------------|
| `ipam_id` | ID of the created IPAM. |
| `ipam_arn` | ARN of the created IPAM. |
| `ipam_scope_id` | ID of the private default scope. |
| `global_pool_id` | ID of the top-level `10.0.0.0/8` global pool. |
| `global_pool_arn` | ARN of the global pool. |
| `regional_pools` | Map of region to pool details (`pool_id`, `pool_arn`, `cidr`). |
| `regional_pool_ids` | Map of region to pool ID for the `/12` regional pools. |
| `shared_pool_id` | ID of the `/12` pool reserved for Shared VPCs. |
| `shared_pool_arn` | ARN of the shared pool. |
| `shared_pool_cidr` | CIDR block assigned to the shared pool. |
| `external_pool_id` | ID of the `/12` pool reserved for External Integrations. |
| `external_pool_arn` | ARN of the external pool. |
| `external_pool_cidr` | CIDR block assigned to the external pool. |
| `allocation_summary` | Summary of all CIDR allocations for documentation. |

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_vpc_ipam` | Main IPAM resource with multi-region operating regions. |
| `aws_vpc_ipam_pool` (global) | Top-level `10.0.0.0/8` pool. |
| `aws_vpc_ipam_pool_cidr` (global) | CIDR assignment for the global pool. |
| `aws_vpc_ipam_pool_cidr_allocation` | Reservations for legacy networks (one per legacy allocation). |
| `aws_vpc_ipam_pool` (regional) | Regional `/12` pools (one per target region). |
| `aws_vpc_ipam_pool_cidr` (regional) | CIDR assignments for regional pools. |
| `aws_vpc_ipam_pool` (shared) | Shared VPC pool. |
| `aws_vpc_ipam_pool_cidr` (shared) | CIDR assignment for the shared pool. |
| `aws_vpc_ipam_pool` (external) | External integrations pool. |
| `aws_vpc_ipam_pool_cidr` (external) | CIDR assignment for the external pool. |

## Capacity Planning

The `10.0.0.0/8` address space contains 16 `/12` blocks. The module enforces:

```
Required capacity = target_regions + auto_allocated_pools
Available capacity = 16 - legacy_allocations - override_allocations

Where:
- auto_allocated_pools = 2 (default) or less if overrides are used
- override_allocations = number of CIDR overrides provided
```

An error is raised if `required_capacity > available_capacity`.

### Example Capacity Calculation

| Scenario | Regions | Legacy | Shared | External | Overrides | Total Used | Remaining |
|----------|---------|--------|--------|----------|-----------|------------|-----------|
| Minimal | 2 | 0 | auto | auto | 0 | 4 | 12 |
| Standard | 4 | 2 | auto | auto | 0 | 8 | 8 |
| With Overrides | 4 | 2 | override | override | 2 | 8 | 8 |
| Max Regions | 14 | 0 | override | override | 2 | 16 | 0 |

## CIDR Math

The module uses Terraform's `cidrsubnet` function to generate `/12` blocks:

```hcl
# cidrsubnet("10.0.0.0/8", 4, n) where n = 0..15
# n=0  -> 10.0.0.0/12
# n=1  -> 10.16.0.0/12
# n=2  -> 10.32.0.0/12
# ...
# n=14 -> 10.224.0.0/12
# n=15 -> 10.240.0.0/12
```

## Integration with Other Modules

This module prepares the IPAM pools but **does not provision VPCs**. Downstream modules should:

1. Reference `regional_pool_ids[region]` to allocate VPC CIDRs from the correct regional pool
2. Reference `shared_pool_id` for Shared VPC allocations
3. Reference `external_pool_id` for external integration networks

### Example: VPC Module Integration

```hcl
module "ipam" {
  source         = "./modules/ipam"
  target_regions = ["us-east-1", "us-west-2"]
}

module "vpc" {
  source = "./modules/vpc"

  ipam_pool_id = module.ipam.regional_pool_ids["us-east-1"]
  netmask_length = 16
}
```

## Tagging

The following tags are automatically applied to all resources:

- `Module` = `ipam`
- `Purpose` = `IP Address Management`
- `Tier` = `global` | `regional` | `shared` | `external`
- `Name` = Resource-specific name
- Plus any tags from `var.tags`

## Limitations

- This module only supports IPv4 (`10.0.0.0/8`)
- All legacy allocations must be `/12` blocks
- Maximum of 16 total `/12` blocks (including legacy, regional, shared, and external)
