# IPAM Module - Agent Guide

## Purpose

This module creates and manages the top-level AWS IPAM (IP Address Management) resource in the Platform Account. It subdivides the `10.0.0.0/8` address space into regional and functional pools.

## Context

- **Provider:** Must be executed with credentials from the **Platform Account**
- **Scope:** IPAM and pool creation only; does NOT provision VPCs
- **Strategy:** Bottom-up allocation for regions, top-down for shared/external pools

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `target_regions` | `list(string)` | Yes | AWS regions to provision regional pools for. |
| `legacy_allocations` | `list(object)` | No | `/12` CIDRs to reserve for legacy networks. |
| `shared_pool_cidr_override` | `string` | No | Override for shared pool CIDR (must be `/12`). |
| `external_pool_cidr_override` | `string` | No | Override for external pool CIDR (must be `/12`). |
| `tags` | `map(string)` | No | Tags to apply to all resources. |

### `legacy_allocations` Object

```hcl
{
  name        = string  # Identifier
  cidr        = string  # Must be /12
  description = string  # Description
}
```

### Override Constraints

- Must be valid `/12` within `10.0.0.0/8`
- Must not overlap with `legacy_allocations`
- `shared_pool_cidr_override` and `external_pool_cidr_override` must be different

## Outputs

| Name | Description |
|------|-------------|
| `ipam_id` | IPAM resource ID. |
| `ipam_arn` | IPAM ARN. |
| `ipam_scope_id` | Private default scope ID. |
| `global_pool_id` | ID of `10.0.0.0/8` global pool. |
| `regional_pools` | Map of `region -> {pool_id, pool_arn, cidr}`. |
| `regional_pool_ids` | Map of `region -> pool_id`. |
| `shared_pool_id` | Shared VPC pool ID. |
| `shared_pool_cidr` | Shared pool CIDR. |
| `external_pool_id` | External integrations pool ID. |
| `external_pool_cidr` | External pool CIDR. |
| `allocation_summary` | Full allocation summary for documentation. |

## Allocation Algorithm

1. Generate all 16 `/12` CIDRs from `10.0.0.0/8`
2. Exclude legacy CIDRs from `var.legacy_allocations`
3. Exclude override CIDRs (if provided)
4. **Bottom-Up:** Assign `target_regions` to lowest available CIDRs
5. **External:** Use override if provided, else highest available CIDR
6. **Shared:** Use override if provided, else second-highest available (or highest if external overridden)

## Pool Hierarchy

```
10.0.0.0/8 (Global)
├── Regional Pools (/12) - one per target_region
├── Shared Pool (/12)    - for Shared VPCs
└── External Pool (/12)  - for VPN/Direct Connect
```

## Validation Rules

- `target_regions` must have at least one region
- `legacy_allocations[*].cidr` must be valid `/12` blocks
- Overrides must be valid `/12` blocks within `10.0.0.0/8`
- Overrides must not overlap with legacy allocations
- Overrides must not be the same CIDR
- Capacity check: `regions + auto_allocated <= 16 - legacy_count - override_count`

## Key Resources

| Resource | Purpose |
|----------|---------|
| `aws_vpc_ipam.this` | Main IPAM with operating regions |
| `aws_vpc_ipam_pool.global` | Top-level `10.0.0.0/8` pool |
| `aws_vpc_ipam_pool.regional[region]` | Per-region `/12` pools |
| `aws_vpc_ipam_pool.shared` | Shared VPC pool |
| `aws_vpc_ipam_pool.external` | External integrations pool |
| `aws_vpc_ipam_pool_cidr_allocation.legacy` | Legacy CIDR reservations |

## Scope Boundaries

This module **only** creates IPAM pools. The following are **out of scope**:

- VPC creation (use downstream VPC modules)
- Subnet allocation (handled by VPC modules via IPAM)
- RAM sharing (handled separately if cross-account)
- Transit Gateway integration

## Common Operations

### Adding a New Region

Add the region to `target_regions`. The next available `/12` (bottom-up) will be assigned.

### Adding Legacy Reservations

Add to `legacy_allocations`. The CIDR will be marked as allocated in the global pool.

### Overriding Shared/External CIDRs

Set `shared_pool_cidr_override` or `external_pool_cidr_override` to a specific `/12` block.
This is useful when you need deterministic CIDR assignments.

### Querying Available Capacity

Use the `allocation_summary` output to see remaining capacity.

## Testing

Run tests with OpenTofu:

```bash
cd terraform/modules/ipam
tofu init -backend=false
tofu test
```

Test files:
- `tests/cidr_math.tftest.hcl` - CIDR calculation unit tests
- `tests/overrides.tftest.hcl` - Override functionality tests
- `tests/integration.tftest.hcl` - Full module integration tests
