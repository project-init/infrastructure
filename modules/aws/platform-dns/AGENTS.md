# Platform DNS Module - Agent Guide

## Purpose

This module manages Route53 Hosted Zones for the Root Domain and Environment-specific subdomains in the Platform Account. It acts as the authoritative source for the organization's DNS structure.

## Context

- **Provider:** Must be executed with credentials from the **Platform Account**
- **Scope:** Creates Route53 Hosted Zones and handles internal delegation (Root -> Environment)
- **Out of Scope:** Sibling account delegations (handled by downstream modules using multi-provider configurations)

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `root_domain` | `string` | Yes | - | The root domain name (e.g., `example.com`). |
| `environments` | `list(string)` | No | `["staging", "production"]` | List of environments to create subdomains for. |
| `tags` | `map(string)` | No | `{}` | Tags to apply to all Hosted Zones. |

## Outputs

| Name | Description |
|------|-------------|
| `root_zone_id` | Hosted Zone ID for the root domain. |
| `root_zone_arn` | ARN of the root hosted zone. |
| `root_zone_name_servers` | Name servers for the root domain (configure at registrar). |
| `env_zone_ids` | Map of `environment -> zone_id`. |
| `env_zone_arns` | Map of `environment -> zone_arn`. |
| `env_zone_names` | Map of `environment -> full_domain_name`. |
| `env_zone_name_servers` | Map of `environment -> name_servers`. |
| `dns_summary` | Full DNS configuration summary for documentation. |

## Resource Hierarchy

```
example.com (Root Zone)
├── NS record: staging.example.com -> Staging Zone NS
├── NS record: production.example.com -> Production Zone NS
└── (other records managed separately)

staging.example.com (Environment Zone)
└── (records managed by workloads)

production.example.com (Environment Zone)
└── (records managed by workloads)
```

## Validation Rules

- `root_domain` must be a valid domain name (no leading/trailing dots)
- `environments` must have at least one entry
- Each environment must be a valid DNS label (lowercase alphanumeric, hyphens allowed but not at start/end)
- Environment names must be unique
- Environment names must be 63 characters or fewer (DNS label limit)

## Key Resources

| Resource | Purpose |
|----------|---------|
| `aws_route53_zone.root` | Hosted Zone for the root domain |
| `aws_route53_zone.environment[env]` | Hosted Zone for each environment subdomain |
| `aws_route53_record.environment_delegation[env]` | NS records delegating to environment zones |

## Scope Boundaries

This module **only** creates zones and internal delegation. The following are **out of scope**:

- DNS records for applications (managed by workload modules)
- Cross-account zone delegation (requires multi-provider setup)
- Domain registration (done at registrar)
- DNSSEC configuration (can be added later)

## Common Operations

### Adding a New Environment

Add the environment name to the `environments` list. The module will create:
1. A new hosted zone for `<env>.<root_domain>`
2. An NS delegation record in the root zone

### Registrar Configuration

After initial deployment, configure your domain registrar with the name servers from the `root_zone_name_servers` output.

### Cross-Account Delegation

For workload accounts that need their own subdomains (e.g., `app.staging.example.com`), use a separate module that:
1. Creates the zone in the target account
2. Uses multi-provider to create NS records in the environment zone

## Testing

Run tests with OpenTofu:

```bash
cd terraform/modules/platform-dns
tofu init -backend=false
tofu test
```
