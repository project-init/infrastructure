# IPAM Module Specification

## 1. Overview
**Purpose**: Manages the top-level IP Address Management (IPAM) within the Platform Account. It subdivides the `10.0.0.0/8` Global Pool into regional `/12` pools and handles shared/external space allocation strategies (Bottom-Up vs Top-Down).

**Context**:
- Deployed in the **Platform Account**.
- Creates the IPAM Scope and Pools.
- DOES NOT provision VPCs; only prepares the pools for consumption.
- Supports skipping CIDR blocks for legacy integration.

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `target_regions` | `list(string)` | **Required** | List of AWS Regions (e.g., `["us-east-1", "us-west-2"]`) to provision pools for. |
| `legacy_allocations` | `list(object)` | `[]` | List of CIDRs (`/12`) to reserve/skip for legacy networks. |
| `tags` | `map(string)` | `{}` | Tags to apply to IPAM resources. |

**`legacy_allocations` Object Structure**:
```hcl
{
  name        = string
  cidr        = string # Must be a /12
  description = string
}
```

## 3. Resources

### `aws_vpc_ipam`
- **Description**: Main IPAM resource.
- **Operating Regions**: Union of `target_regions` and current region.

### `aws_vpc_ipam_pool` (Global)
- **Address Family**: `ipv4`
- **CIDR**: `10.0.0.0/8`
- **Publicly Advertisable**: `false`

### `aws_vpc_ipam_pool_cidr_allocation` (Legacy Reservations)
- **Pool ID**: Global Pool ID
- **CIDR**: Derived from `var.legacy_allocations`.
- **Description**: Reserved for legacy network `${item.name}`.

### `aws_vpc_ipam_pool` (Regional Pools - "Bottom-Up")
- **Strategy**: 
  - Iterate through `10.0.0.0/8` in `/12` increments.
  - Skip any CIDR present in `var.legacy_allocations`.
  - Assign the first available `/12` to the first region in `var.target_regions`.
  - Repeat for subsequent regions.
- **Attributes**:
  - **Locale**: `${region_name}`
  - **Source IPAM Pool**: Global Pool ID.

### `aws_vpc_ipam_pool` (Shared Pool - "Top-Down")
- **Strategy**:
  - Start from the *highest* available `/12` in the `10.0.0.0/8` space (normally `10.224.0.0/12` if no legacy blocks block it).
  - This pool is **Global** (no locale set?) or Multi-Region? 
  - *Correction based on Text*: "Each of these need a shared VPC... The first /12 chosen will be the top one... We're going to divide each /12 into two /13 (lower/upper)... The shared space will be allocated into /15".
  - *Refined Logic*: This module creates a **Shared Pool** (e.g., `10.224.0.0/12`) intended for Shared VPCs. 
  - Sub-pools for regions within this Shared Pool are `/15`s.

### `aws_vpc_ipam_pool` (External/Integrations)
- **Strategy**:
  - Allocated from the very top of the band (e.g., `10.240.0.0/12`).
  - Shifts down if legacy blocks occupy the top.

## 4. Outputs

| Name | Description |
|------|-------------|
| `ipam_id` | ID of the created IPAM. |
| `global_pool_id` | ID of the Top-Level `10.0.0.0/8` pool. |
| `regional_pools` | Map of `region -> pool_id` for the `/12` regional pools. |
| `shared_pool_id` | ID of the `/12` pool reserved for Shared VPCs. |
| `external_pool_id` | ID of the `/12` pool reserved for External Integrations. |

## 5. Implementation Notes
- **CIDR Math**: This is the most complex part. Use `cidrsubnets` or `cidrsubnet` extensively.
- **Algorithm**:
  1. Generate all sixteen `/12` CIDRs from `10.0.0.0/8`.
  2. Filter out those in `var.legacy_allocations`.
  3. `available_cidrs` = `all_cidrs - legacy_cidrs`.
  4. Assign `target_regions` to the *lowest* available CIDRs in `available_cidrs`.
  5. Assign `External` pool to the *highest* available CIDR.
  6. Assign `Shared` pool to the *next highest* available CIDR.
- **Validation**: Ensure `length(target_regions) + length(legacy_allocations) + 2 (Shared+External) <= 16`. Error if capacity is exceeded.
