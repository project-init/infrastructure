# Platform DNS Module

Manages Route53 Hosted Zones for your organization's root domain and environment-specific subdomains.

## What This Module Does

This module creates a centralized DNS structure in your Platform Account:

1. **Root Hosted Zone** - The authoritative zone for your domain (e.g., `example.com`)
2. **Environment Hosted Zones** - Subdomains for each environment (e.g., `staging.example.com`, `production.example.com`)
3. **Delegation Records** - NS records that delegate authority from the root zone to each environment zone

```
example.com (Root Zone)
    |
    +-- NS record --> staging.example.com (Environment Zone)
    |
    +-- NS record --> production.example.com (Environment Zone)
```

## Usage

```hcl
module "platform_dns" {
  source = "./modules/platform-dns"

  root_domain  = "example.com"
  environments = ["staging", "production"]

  tags = {
    Team = "Platform"
  }
}
```

After applying, configure your domain registrar with the name servers from the output. You'll need to expose the module's output in your root configuration:

```hcl
# In your root module
output "root_zone_name_servers" {
  value = module.platform_dns.root_zone_name_servers
}
```

Then retrieve it:

```bash
tofu output root_zone_name_servers
```

## Requirements

| Name | Version |
|------|---------|
| terraform/opentofu | >= 1.0 |
| aws | ~> 6.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| `root_domain` | The root domain name (e.g., `example.com`) | `string` | - | yes |
| `environments` | List of environments to create subdomains for | `list(string)` | `["staging", "production"]` | no |
| `tags` | Tags to apply to all Hosted Zones | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| `root_zone_id` | Hosted Zone ID for the root domain |
| `root_zone_arn` | ARN of the root hosted zone |
| `root_zone_name_servers` | Name servers to configure at your registrar |
| `env_zone_ids` | Map of environment name to zone ID |
| `env_zone_arns` | Map of environment name to zone ARN |
| `env_zone_names` | Map of environment name to full domain name |
| `env_zone_name_servers` | Map of environment name to name servers |
| `dns_summary` | Complete DNS configuration summary |

## After Deployment

### 1. Update Your Domain Registrar

Copy the name servers from `root_zone_name_servers` and configure them at your domain registrar. DNS propagation typically takes 24-48 hours.

### 2. Verify Delegation

Check that the delegation is working:

```bash
# Check root zone
dig NS example.com

# Check environment zone delegation
dig NS staging.example.com
```

### 3. Add Application Records

Application teams can now create records in their environment zones. Pass the appropriate `env_zone_ids` output to downstream modules.

## What This Module Does NOT Do

- **Domain Registration** - Register your domain separately with a registrar
- **Application DNS Records** - Managed by workload-specific modules
- **Cross-Account Delegation** - For workload accounts needing their own subzones, use a separate module with multi-provider configuration
- **DNSSEC** - Can be enabled separately if needed

## Adding a New Environment

Simply add the environment name to the `environments` list:

```hcl
environments = ["staging", "production", "development"]
```

The module will create the new hosted zone and delegation record automatically.
