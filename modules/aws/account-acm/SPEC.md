# Account ACM Module Specification

## 1. Overview

**Purpose**: Provisions wildcard ACM certificates for sibling account namespaces. Handles DNS validation across both the sibling account's hosted zone and the platform account's root zone (for production rollup records).

**Context**:
- Deployed in the **Sibling Account** (certificate lives here).
- Validation records span two accounts:
  - Subdomain validation → Sibling account's hosted zone
  - Root wildcard validation → Platform account's root zone (production only)
- **Providers**: Requires two providers:
  - `aws`: The Sibling Account (default) - certificate and subdomain validation records
  - `aws.platform`: The Platform Account - root wildcard validation records

**Use Case**:
Enables services in sibling accounts to serve HTTPS traffic on:
- `{namespace}.{environment}.{root_domain}` (e.g., `core.staging.example.com`)
- `*.{namespace}.{environment}.{root_domain}` (e.g., `api.core.staging.example.com`)
- `*.{root_domain}` (production only, e.g., `api.example.com` via CNAME to `api.core.production.example.com`)

## 2. Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `namespace` | `string` | - | Yes | The account namespace (e.g., `core`, `analytics`). |
| `environment` | `string` | - | Yes | The environment: `staging` or `production`. |
| `root_domain` | `string` | - | Yes | The root domain (e.g., `example.com`). |
| `sibling_zone_id` | `string` | - | Yes | Hosted Zone ID in the sibling account for `{namespace}.{environment}.{root_domain}`. |
| `platform_root_zone_id` | `string` | - | Yes | Hosted Zone ID in the platform account for `{root_domain}`. Required even for non-production (simplifies interface). |
| `tags` | `map(string)` | `{}` | No | Tags to apply to the ACM certificate. |

### Input Validation

- `environment` must be one of: `staging`, `production`
- `root_domain` must not start with a dot
- `namespace` must be lowercase alphanumeric with hyphens allowed

## 3. Resources

### ACM Certificate (Provider: `aws` - Sibling)

| Attribute | Value |
|-----------|-------|
| **Domain Name** | `{namespace}.{environment}.{root_domain}` (primary certificate domain) |
| **Subject Alternative Names** | Wildcard domains only; see table below |
| **Validation Method** | DNS |
| **Tags** | Merged from `var.tags` + `Name = {namespace}-{environment}-certificate` |

> **Note**: The certificate's primary `domain_name` is `{namespace}.{environment}.{root_domain}`. The following wildcard domains are configured as Subject Alternative Names (SANs):

| Environment | Wildcard SANs |
|-------------|---------------|
| All | `*.{namespace}.{environment}.{root_domain}` |
| Production only | `*.{root_domain}` |

### DNS Validation Records

#### Subdomain Validation (Provider: `aws` - Sibling)

- **Zone ID**: `var.sibling_zone_id`
- **Records**: DNS validation records for the primary domain and subdomain wildcard, using `domain_validation_options[*].resource_record_name` and `resource_record_value`
- **Type**: Use `domain_validation_options[*].resource_record_type` (typically `CNAME`; do not hard-code)
- **TTL**: `60`

#### Root Wildcard Validation (Provider: `aws.platform` - Platform)

- **Condition**: Only when `var.environment == "production"`
- **Zone ID**: `var.platform_root_zone_id`
- **Records**: DNS validation record for `*.{root_domain}`, using the appropriate `resource_record_name` and `resource_record_value` from `domain_validation_options[*]`
- **Type**: Use `domain_validation_options[*].resource_record_type` (typically `CNAME`; do not hard-code)
- **TTL**: `60`

### Certificate Validation (Provider: `aws` - Sibling)

- **Resource**: `aws_acm_certificate_validation`
- **Purpose**: Waits for all validation records to propagate and certificate to be issued
- **Timeout**: Default (75 minutes)

## 4. Outputs

| Name | Type | Description |
|------|------|-------------|
| `certificate_arn` | `string` | The ARN of the validated ACM certificate. |
| `certificate_domain_name` | `string` | The primary domain name of the certificate. |
| `certificate_sans` | `list(string)` | List of Subject Alternative Names on the certificate. |
| `certificate_status` | `string` | The status of the certificate (should be `ISSUED` after apply). |

## 5. Dependencies

### Module Dependencies
- Depends on the `dns` module (for platform root zone) being applied first
- Depends on sibling account hosted zone existing (created by `account-baseline` or similar)

### Provider Requirements
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
      configuration_aliases = [aws.platform]
    }
  }
}
```

## 6. Naming Convention

| Resource | Name Pattern |
|----------|--------------|
| Certificate | `{namespace}-{environment}-certificate` (tag only, ACM doesn't have name attribute) |
| Validation Records | Determined by AWS (CNAME name from `domain_validation_options`) |

## 7. Usage Example

```hcl
module "account_acm" {
  source = "./modules/account-acm"

  namespace   = "core"
  environment = "production"
  root_domain = "example.com"

  sibling_zone_id        = module.account_baseline.hosted_zone_id
  platform_root_zone_id  = data.terraform_remote_state.platform.outputs.root_zone_id

  tags = {
    Team = "platform"
  }

  providers = {
    aws          = aws.core_production
    aws.platform = aws.platform
  }
}

# Use the certificate ARN
resource "aws_lb_listener" "https" {
  # ...
  certificate_arn = module.account_acm.certificate_arn
}
```

### Production Rollup Pattern

With this module, production accounts can expose services on the root domain:

```
# DNS setup (manual or via separate config):
# api.example.com CNAME -> api.core.production.example.com

# The ACM certificate covers both:
# - api.core.production.example.com (via *.core.production.example.com SAN)
# - api.example.com (via *.example.com SAN)
```

## 8. Implementation Notes

### Validation Record Deduplication

ACM may return duplicate validation options for the primary domain and wildcard (they often share the same validation record). Use `distinct()` or a `for_each` with a map keyed by the validation record name to avoid creating duplicate DNS records.

Example pattern:
```hcl
locals {
  # Deduplicate validation options by record name
  sibling_validation_options = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.resource_record_name => dvo
    if endswith(dvo.domain_name, "${var.namespace}.${var.environment}.${var.root_domain}")
  }
  
  platform_validation_options = {
    for dvo in aws_acm_certificate.this.domain_validation_options :
    dvo.resource_record_name => dvo
    if dvo.domain_name == "*.${var.root_domain}"
  }
}
```

### Provider Alias Declaration

The module must declare the required provider alias as described in the **Provider Requirements** section above.

### Conditional Root Wildcard

Use conditional logic to include the root wildcard SAN only for production:
```hcl
subject_alternative_names = concat(
  ["*.${var.namespace}.${var.environment}.${var.root_domain}"],
  var.environment == "production" ? ["*.${var.root_domain}"] : []
)
```

### Certificate Validation Resource

The `aws_acm_certificate_validation` resource must reference all validation record FQDNs from both zones. Use `for_each` for the platform validation records (with an empty map for non-production) to ensure the resource is always iterable:

```hcl
# Platform validation records use for_each with conditional map
resource "aws_route53_record" "platform_validation" {
  for_each = var.environment == "production" ? local.platform_validation_options : {}
  # ...
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = concat(
    [for r in aws_route53_record.sibling_validation : r.fqdn],
    [for r in aws_route53_record.platform_validation : r.fqdn]  # Empty when not production
  )
}
```

## 9. Out of Scope

- **Hosted zone creation**: Zones must exist before calling this module
- **DNS records for services**: This module only creates validation records, not A/CNAME records for actual services
- **Private CA certificates**: This is for public ACM certificates only (future `platform-acm` module may handle private CA)
- **Cross-region certificates**: Certificate is created in the provider's configured region only
- **Certificate renewal**: ACM handles automatic renewal; this module doesn't manage that lifecycle
- **Non-wildcard certificates**: This module always creates wildcard certificates per the defined pattern

## 10. Testing Considerations

- Test with both `staging` and `production` environments to verify conditional SAN logic
- Verify validation records are created in the correct zones
- Confirm certificate reaches `ISSUED` status
- Test that the `platform_root_zone_id` is not used for non-production validation records
