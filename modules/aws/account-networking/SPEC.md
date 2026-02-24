# Account Networking Specification

## 1. Overview

**Purpose**: Provisions per-region networking infrastructure for a Sibling Account within a shared Platform VPC. It allocates IP space from IPAM, creates subnets in the Platform VPC, associates them with existing route tables, and shares them to the Sibling Account via RAM.

**Context**:
- Extracted from the `account-baseline` module to enable multi-region deployments. Each region an organization supports gets its own instance of this module.
- Deployed across two AWS accounts using dual providers:
  - `aws`: The Sibling Account (default). Used for RAM share acceptance and subnet re-tagging.
  - `aws.platform`: The Platform Account. Used for IPAM allocation, subnet creation, route table associations, and RAM resource sharing.
- The caller controls which region the module operates in by configuring the providers' regions. The module itself has no region input.

**Dependency Chain**:
```
ipam (Platform Account)
  └─ Outputs: regional_pool_ids
       │
       ▼
platform-networking (Platform Account)
  └─ Outputs: vpc_id, public_route_table_id, private_route_table_ids
       │
       ▼
account-networking (Platform + Sibling Account)  ← THIS MODULE
  └─ Inputs: ipam_pool_id, vpc_id, public_route_table_id, private_route_table_ids
  └─ Outputs: vpc_id, public_subnets, private_subnets, ipam_allocation_cidr
```

## 2. Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `namespace` | `string` | -- | Yes | The account namespace (e.g., `core`). Used in resource naming. |
| `environment` | `string` | -- | Yes | `staging` or `production`. Validated. Used in resource naming. |
| `ipam_pool_id` | `string` | -- | Yes | The ID of the IPAM Pool to allocate from (Lower or Upper). |
| `vpc_id` | `string` | -- | Yes | The ID of the Platform VPC to create subnets in. |
| `public_route_table_id` | `string` | -- | Yes | The ID of the public route table in the Platform VPC. |
| `private_route_table_ids` | `list(string)` | -- | Yes | List of private route table IDs in the Platform VPC (min 1). Uses `element()` to wrap around if fewer than `subnet_count`. |
| `subnet_count` | `number` | `3` | No | Number of public and private subnets to create (1-4). Constrained by /24 allocation with /27 subnets. |
| `subnet_netmask_length` | `number` | `24` | No | Netmask length for the IPAM allocation. |
| `accept_ram_share` | `bool` | `false` | No | Whether to explicitly accept the RAM share in the sibling account. Set to `false` when AWS Organizations auto-accept is enabled. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to all resources. |

### Validation Rules

- `environment`: Must be one of `["staging", "production"]`.
- `private_route_table_ids`: Must have at least 1 entry.
- `subnet_count`: Must be between 1 and 4.

## 3. Resources

All resources are extracted directly from `account-baseline/networking.tf`.

### Locals

| Name | Value | Description |
|------|-------|-------------|
| `resource_prefix` | `"${var.namespace}-${var.environment}"` | Naming prefix for all resources. |
| `azs` | `data.aws_availability_zones.available.names` | Available AZs in the provider's region. |
| `subnet_bits` | `3` | Subnet bits for CIDR calculation (/24 + 3 = /27). |

### Data Sources

| Resource | Provider | Purpose |
|----------|----------|---------|
| `aws_caller_identity.current` | `aws` (sibling) | Gets the Sibling Account ID for RAM principal association. |
| `aws_availability_zones.available` | `aws.platform` | Fetches available AZs in the target region. |

### IPAM Allocation (Provider: `aws.platform`)

| Resource | Description |
|----------|-------------|
| `aws_vpc_ipam_pool_cidr_allocation.this` | Allocates a CIDR block (default /24) from the specified IPAM pool. Description set to "Allocation for `${resource_prefix}`". |

### Subnets (Provider: `aws.platform`)

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_subnet.public` | `var.subnet_count` | Public subnets carved from the IPAM allocation using `cidrsubnet()`. Indices 0 through subnet_count-1. `map_public_ip_on_launch = true`. Tagged with `kubernetes.io/role/elb = 1`. |
| `aws_subnet.private` | `var.subnet_count` | Private subnets carved from the IPAM allocation using `cidrsubnet()`. Indices subnet_count through 2*subnet_count-1. Tagged with `kubernetes.io/role/internal-elb = 1`. |

**Naming**: `${resource_prefix}-public-${index+1}`, `${resource_prefix}-private-${index+1}`

**AZ Distribution**: `element(local.azs, count.index)` to spread across AZs.

### Route Table Associations (Provider: `aws.platform`)

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_route_table_association.public` | `var.subnet_count` | Associates each public subnet with `var.public_route_table_id`. |
| `aws_route_table_association.private` | `var.subnet_count` | Associates each private subnet with `element(var.private_route_table_ids, count.index)`. |

### RAM Sharing (Provider: `aws.platform`)

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_ram_resource_share.subnets` | 1 | Creates a RAM resource share named `${resource_prefix}-subnets`. `allow_external_principals = false`. |
| `aws_ram_resource_association.public_subnets` | `var.subnet_count` | Associates public subnet ARNs with the RAM share. |
| `aws_ram_resource_association.private_subnets` | `var.subnet_count` | Associates private subnet ARNs with the RAM share. |
| `aws_ram_principal_association.sibling_account` | 1 | Associates the Sibling Account ID as a RAM principal. |

### RAM Share Acceptance (Provider: `aws` - Sibling)

| Resource | Count | Description |
|----------|-------|-------------|
| `aws_ram_resource_share_accepter.subnets` | 0 or 1 | Accepts the RAM share when `var.accept_ram_share = true`. |

### Subnet Re-Tagging (Provider: `aws` - Sibling)

| Resource | Description |
|----------|-------------|
| `time_sleep.wait_for_ram_share` | 30-second delay after RAM principal association to allow propagation. |
| `aws_ec2_tag.public_subnet` | Re-applies tags to public subnets in the sibling account (RAM sharing drops tags). Uses `for_each` over flattened subnet-index/tag-key pairs. |
| `aws_ec2_tag.private_subnet` | Re-applies tags to private subnets in the sibling account. Same pattern as public. |

## 4. Outputs

| Name | Description | Value |
|------|-------------|-------|
| `vpc_id` | The ID of the VPC (pass-through from `var.vpc_id`). | `var.vpc_id` |
| `public_subnets` | List of public subnet IDs (shared from Platform). | `aws_subnet.public[*].id` |
| `private_subnets` | List of private subnet IDs (shared from Platform). | `aws_subnet.private[*].id` |
| `ipam_allocation_cidr` | The CIDR block allocated from IPAM. | `aws_vpc_ipam_pool_cidr_allocation.this.cidr` |

## 5. Providers

This module requires two provider configurations:

| Alias | Description |
|-------|-------------|
| `aws` | Default provider for the Sibling Account. Used for RAM acceptance and subnet re-tagging. |
| `aws.platform` | Provider for the Platform Account. Used for IPAM, subnets, route tables, and RAM sharing. |

Declared in `versions.tf` via `configuration_aliases = [aws.platform]`.

**Required Providers**:
- `hashicorp/aws` >= 5.0
- `hashicorp/time` >= 0.9

## 6. Naming Convention

All resources follow the pattern: `${var.namespace}-${var.environment}-<resource-type>-<index>`

Examples:
- Subnets: `core-staging-public-1`, `core-staging-private-2`
- RAM Share: `core-staging-subnets`

## 7. Tagging

All resources receive `var.tags` merged with resource-specific tags:

| Tag | Applied To | Value |
|-----|-----------|-------|
| `Name` | All resources | Resource-specific name |
| `Type` | Subnets | `public` or `private` |
| `kubernetes.io/role/elb` | Public subnets | `1` |
| `kubernetes.io/role/internal-elb` | Private subnets | `1` |

## 8. Usage Example

```hcl
# Single-region deployment
module "account_networking" {
  source = "./modules/account-networking"

  providers = {
    aws          = aws.sibling
    aws.platform = aws.platform
  }

  namespace   = "core"
  environment = "staging"

  ipam_pool_id           = module.ipam.regional_pool_ids["lower"]
  vpc_id                 = module.platform_networking.vpc_ids["lower"]
  public_route_table_id  = module.platform_networking.public_route_table_ids["lower"]
  private_route_table_ids = module.platform_networking.private_route_table_ids["lower"]

  tags = {
    Module      = "account-networking"
    Environment = "staging"
  }
}

# Multi-region deployment
module "account_networking_us_east_1" {
  source = "./modules/account-networking"

  providers = {
    aws          = aws.sibling_us_east_1
    aws.platform = aws.platform_us_east_1
  }

  namespace   = "core"
  environment = "staging"

  ipam_pool_id           = module.ipam.regional_pool_ids["lower"]
  vpc_id                 = module.platform_networking_us_east_1.vpc_ids["lower"]
  public_route_table_id  = module.platform_networking_us_east_1.public_route_table_ids["lower"]
  private_route_table_ids = module.platform_networking_us_east_1.private_route_table_ids["lower"]

  tags = {
    Module      = "account-networking"
    Environment = "staging"
    Region      = "us-east-1"
  }
}

module "account_networking_us_west_2" {
  source = "./modules/account-networking"

  providers = {
    aws          = aws.sibling_us_west_2
    aws.platform = aws.platform_us_west_2
  }

  namespace   = "core"
  environment = "staging"

  ipam_pool_id           = module.ipam.regional_pool_ids["lower"]
  vpc_id                 = module.platform_networking_us_west_2.vpc_ids["lower"]
  public_route_table_id  = module.platform_networking_us_west_2.public_route_table_ids["lower"]
  private_route_table_ids = module.platform_networking_us_west_2.private_route_table_ids["lower"]

  tags = {
    Module      = "account-networking"
    Environment = "staging"
    Region      = "us-west-2"
  }
}
```

## 9. Testing

Tests should be written as `tftest.hcl` files under `tests/` with a `setup/` subdirectory for test infrastructure.

### Test Setup (`tests/setup/main.tf`)
The setup module should create the minimum infrastructure needed:
- A mock VPC (or use a `terraform_data` resource for plan-only tests)
- Mock route tables
- Mock IPAM pool (if feasible, or use `terraform_data` placeholders)

### Test Cases

| Test | Description |
|------|-------------|
| `defaults` | Verify the module applies with default `subnet_count=3` and `accept_ram_share=false`. Assert correct number of subnets, route table associations, and RAM resources. |
| `custom_subnet_count` | Set `subnet_count=2` and verify only 2 public + 2 private subnets are created. |
| `ram_share_acceptance` | Set `accept_ram_share=true` and verify the `aws_ram_resource_share_accepter` resource is created. |
| `validation_subnet_count` | Verify that `subnet_count=0` and `subnet_count=5` are rejected by validation. |
| `validation_environment` | Verify that an invalid environment value is rejected. |
| `validation_private_rt_ids` | Verify that an empty `private_route_table_ids` list is rejected. |

### Notes
- Due to the cross-account nature of this module (RAM sharing between Platform and Sibling accounts), full integration tests require both provider configurations. Plan-only tests may be more practical for CI.
- The `time_sleep` resource will add 30 seconds to any apply-based test run.

## 10. Implementation Notes

- **Direct extraction**: The implementation should be a direct lift of `account-baseline/networking.tf` into the new module. No behavioral changes.
- **Provider aliases**: Declared via `configuration_aliases` in `versions.tf`, not via provider blocks in the module (per repo convention in `terraform/modules/AGENTS.md`).
- **File structure**: Follow the repo convention:
  - `main.tf` -- All resources (single-concern module, no need to split).
  - `variables.tf` -- All input variables with validation blocks.
  - `outputs.tf` -- All outputs.
  - `versions.tf` -- Required providers with `configuration_aliases`.
  - `SPEC.md` -- This file.
  - `AGENTS.md` -- Agent instructions for AI tools.
  - `README.md` -- Human-readable documentation.
  - `tests/` -- Test files.

## 11. Out of Scope

- VPC creation (handled by `platform-networking`).
- Internet Gateways, NAT Gateways, route tables (handled by `platform-networking`).
- Security groups.
- Transit Gateway attachments or VPC peering.
- DNS zones and delegation (remains in `account-baseline`).
- ACM certificates (remains in `account-baseline`).
- S3 state bucket (remains in `account-baseline`).
- Refactoring `account-baseline` to remove networking (separate effort).
