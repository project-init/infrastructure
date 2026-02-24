# DNS Module Specification

## 1. Overview
**Purpose**: Manages the Root Domain and Environment-specific subdomains in the Platform Account. It acts as the authoritative source for the organization's DNS structure.

**Context**:
- Deployed in the **Platform Account**.
- Creates Route53 Hosted Zones for the Root (e.g., `example.com`) and Environments (e.g., `staging.example.com`).
- Handles internal delegation (Root -> Env).
- **Does NOT** handle sibling account delegations (that is done by downstream modules using multi-provider configurations).

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `root_domain` | `string` | **Required** | The root domain name (e.g., `example.com`). |
| `environments` | `list(string)` | `["staging", "production"]` | List of environments to create subdomains for. |
| `tags` | `map(string)` | `{}` | Tags to apply to Hosted Zones. |

## 3. Resources

### `aws_route53_zone` (Root)
- **Name**: `${var.root_domain}`
- **Comment**: Managed by Platform DNS Module.

### `aws_route53_zone` (Environments)
- **Count**: One per entry in `var.environments`.
- **Name**: `${env}.${var.root_domain}` (e.g., `staging.example.com`).
- **Comment**: Environment Subdomain for `${env}`.

### `aws_route53_record` (Environment Delegation)
- **Zone ID**: Root Zone ID.
- **Name**: `${env}.${var.root_domain}`.
- **Type**: `NS`.
- **TTL**: `300` (or reasonable default).
- **Records**: Use the `name_servers` from the created Environment Zone.

## 4. Outputs

| Name | Description |
|------|-------------|
| `root_zone_id` | Hosted Zone ID for the root domain. |
| `env_zone_ids` | Map of `environment -> zone_id` for the created environment subdomains. |
| `env_zone_names` | Map of `environment -> full_domain_name`. |

## 5. Implementation Notes
- Use `for_each` for the environment zones to allow easy expansion.
- Ensure the delegation record in the Root zone correctly references the Name Servers of the child Environment zone.
