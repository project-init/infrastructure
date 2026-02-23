# Platform Networking Specification

## 1. Overview
**Purpose**: Provisions the core VPC infrastructure for the Platform (Lower, Upper, and Shared tiers). It handles the complexity of attaching multiple `/16` CIDRs to simulate larger networks and manages IPAM allocations.

**Context**:
- Deployed in the **Platform Account** (Regional).
- Consumes IPAM Pools created by the IPAM module.
- Creates 3 VPCs: `lower`, `upper`, `shared`.
- Manages Subnets (`/27`s from a `/24`) and NAT Gateways with configurable HA strategies.

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `ipam_pool_ids` | `object` | **Required** | Map containing `lower_pool_id`, `upper_pool_id`, `shared_pool_id`. |
| `initial_cidr_count` | `number` | `5` | Number of secondary `/16` CIDRs to attach to VPCs initially (max 5 without quota increase). |
| `nat_gateway_count_lower` | `number` | `1` | Number of NAT Gateways for the Lower VPC. |
| `nat_gateway_count_upper` | `number` | `0` | Number of NAT Gateways for the Upper VPC. |
| `nat_gateway_count_shared` | `number` | `0` | Number of NAT Gateways for the Shared VPC. |
| `tags` | `map(string)` | `{}` | Tags to apply to resources. |

## 3. Resources

### VPCs (`lower`, `upper`, `shared`)
- **Primary CIDR**: Allocated from IPAM (first `/16`).
- **Secondary CIDRs**: `var.initial_cidr_count - 1` additional `/16`s allocated from IPAM.
- **DNS Support**: Enabled.

### IPAM Allocations
- **Allocation Type**: Custom Allocation (for the `/24` subnet spaces).
- **Source**: Respective IPAM Pools.
- **Size**: `/24` per VPC.

### Subnets
- **Strategy**:
  - The allocated `/24` is divided into `/27`s.
  - **Count**: 6 Subnets total (3 Public, 3 Private).
  - **Distribution**: Spread across 3 Availability Zones (AZs).
    - AZ-a: Public-1, Private-1
    - AZ-b: Public-2, Private-2
    - AZ-c: Public-3, Private-3
- **Map Public IP**: `true` for Public subnets.

### Gateways & Routing
- **Internet Gateway**: 1 per VPC.
- **NAT Gateways**:
  - **Count**: Controlled by `var.nat_gateway_count_*`.
  - **Placement**: Placed in Public Subnets (cycling through AZs).
- **Route Tables**:
  - **Public**: 1 RT per VPC (Target: IGW).
  - **Private**: 3 RTs per VPC (one per subnet).
  - **Routing Logic**:
    - Use `element(nat_gateway_ids, index)` to distribute private subnets across available NAT Gateways.
    - If `count=1`: All 3 private subnets route to NATGW-1.
    - If `count=2`: Subnet 1->NAT1, Subnet 2->NAT2, Subnet 3->NAT1.
    - If `count=3`: 1:1 Mapping (Full HA).

## 4. Outputs

| Name | Description |
|------|-------------|
| `vpc_ids` | Map of VPC IDs (`lower`, `upper`, `shared`). |
| `public_subnets` | Map of Public Subnet IDs. |
| `private_subnets` | Map of Private Subnet IDs. |
| `nat_gateway_ips` | List of NAT Gateway Elastic IPs. |

## 5. Implementation Notes
- **NAT Distribution**: The `element()` function approach ensures that reducing NAT count degrades gracefully (fails over to remaining NATs) and increasing it scales up to full HA.
- **CIDR Attachments**: Use `aws_vpc_ipv4_cidr_block_association` for the secondary CIDRs.
- **AZ Lookup**: Use `data "aws_availability_zones"` to fetch the first 3 AZs dynamically.
