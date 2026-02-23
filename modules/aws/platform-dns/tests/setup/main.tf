#------------------------------------------------------------------------------
# Test Setup Module
# Exposes the DNS module logic for unit testing without AWS resources
# Uses mock data to simulate Route53 zone behavior
#------------------------------------------------------------------------------

variable "root_domain" {
  description = "The root domain name"
  type        = string
}

variable "environments" {
  description = "List of environments to create subdomains for"
  type        = list(string)
  default     = ["staging", "production"]
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}

locals {
  # Validation: lowercase check
  is_lowercase = var.root_domain == lower(var.root_domain)

  # Validation: valid domain format (same regex as module)
  is_valid_domain_format = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.root_domain))

  # Validation: no leading/trailing dots
  no_leading_dot  = !startswith(var.root_domain, ".")
  no_trailing_dot = !endswith(var.root_domain, ".")

  # Combined domain validation
  is_valid_root_domain = (
    local.is_lowercase &&
    local.is_valid_domain_format &&
    local.no_leading_dot &&
    local.no_trailing_dot
  )

  # Environment validations
  has_environments = length(var.environments) > 0

  environments_are_valid_labels = alltrue([
    for env in var.environments :
    can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", env))
  ])

  environments_within_length = alltrue([
    for env in var.environments :
    length(env) <= 63
  ])

  environments_are_unique = length(var.environments) == length(distinct(var.environments))

  # Combined environment validation
  is_valid_environments = (
    local.has_environments &&
    local.environments_are_valid_labels &&
    local.environments_within_length &&
    local.environments_are_unique
  )

  # Overall validation
  is_valid = local.is_valid_root_domain && local.is_valid_environments

  # Common tags (same as module)
  common_tags = merge(
    {
      Module  = "platform-dns"
      Purpose = "DNS Management"
    },
    var.tags
  )

  # Environment domain names map (use distinct to allow testing duplicate detection)
  env_domain_names = {
    for env in distinct(var.environments) : env => "${env}.${var.root_domain}"
  }

  # Mock zone IDs (simulating what AWS would return)
  # Use uppercase hex from md5 hash to create deterministic but unique zone IDs
  mock_root_zone_id = "Z${upper(substr(md5(var.root_domain), 0, 13))}"

  mock_env_zone_ids = {
    for env in distinct(var.environments) :
    env => "Z${upper(substr(md5(local.env_domain_names[env]), 0, 13))}"
  }

  # Mock name servers (simulating AWS Route53 NS format with static but realistic values)
  mock_root_name_servers = [
    "ns-1234.awsdns-12.com",
    "ns-5678.awsdns-34.net",
    "ns-9012.awsdns-56.org",
    "ns-3456.awsdns-78.co.uk",
  ]

  mock_env_name_servers = {
    for env in distinct(var.environments) :
    env => [
      "ns-${1000 + index(distinct(var.environments), env)}.awsdns-01.com",
      "ns-${2000 + index(distinct(var.environments), env)}.awsdns-02.net",
      "ns-${3000 + index(distinct(var.environments), env)}.awsdns-03.org",
      "ns-${4000 + index(distinct(var.environments), env)}.awsdns-04.co.uk",
    ]
  }

  # Expected resource counts
  expected_zone_count              = 1 + length(var.environments) # root + environments
  expected_delegation_record_count = length(var.environments)
}

#------------------------------------------------------------------------------
# Validation Outputs
#------------------------------------------------------------------------------
output "is_lowercase" {
  description = "Whether root_domain is lowercase"
  value       = local.is_lowercase
}

output "is_valid_domain_format" {
  description = "Whether root_domain matches valid domain regex"
  value       = local.is_valid_domain_format
}

output "no_leading_dot" {
  description = "Whether root_domain has no leading dot"
  value       = local.no_leading_dot
}

output "no_trailing_dot" {
  description = "Whether root_domain has no trailing dot"
  value       = local.no_trailing_dot
}

output "is_valid_root_domain" {
  description = "Whether root_domain passes all validations"
  value       = local.is_valid_root_domain
}

output "has_environments" {
  description = "Whether at least one environment is specified"
  value       = local.has_environments
}

output "environments_are_valid_labels" {
  description = "Whether all environments are valid DNS labels"
  value       = local.environments_are_valid_labels
}

output "environments_within_length" {
  description = "Whether all environments are within 63 char limit"
  value       = local.environments_within_length
}

output "environments_are_unique" {
  description = "Whether all environments are unique"
  value       = local.environments_are_unique
}

output "is_valid_environments" {
  description = "Whether environments pass all validations"
  value       = local.is_valid_environments
}

output "is_valid" {
  description = "Whether the entire configuration is valid"
  value       = local.is_valid
}

#------------------------------------------------------------------------------
# Domain Name Outputs
#------------------------------------------------------------------------------
output "root_domain" {
  description = "The root domain"
  value       = var.root_domain
}

output "env_domain_names" {
  description = "Map of environment -> full domain name"
  value       = local.env_domain_names
}

#------------------------------------------------------------------------------
# Mock Zone Outputs (simulating AWS responses)
#------------------------------------------------------------------------------
output "mock_root_zone_id" {
  description = "Mock zone ID for root domain"
  value       = local.mock_root_zone_id
}

output "mock_env_zone_ids" {
  description = "Mock zone IDs for environment domains"
  value       = local.mock_env_zone_ids
}

output "mock_root_name_servers" {
  description = "Mock name servers for root domain"
  value       = local.mock_root_name_servers
}

output "mock_env_name_servers" {
  description = "Mock name servers for environment domains"
  value       = local.mock_env_name_servers
}

#------------------------------------------------------------------------------
# Resource Count Outputs
#------------------------------------------------------------------------------
output "expected_zone_count" {
  description = "Expected total number of hosted zones"
  value       = local.expected_zone_count
}

output "expected_delegation_record_count" {
  description = "Expected number of NS delegation records"
  value       = local.expected_delegation_record_count
}

output "environment_count" {
  description = "Number of environments"
  value       = length(var.environments)
}

#------------------------------------------------------------------------------
# Tag Outputs
#------------------------------------------------------------------------------
output "common_tags" {
  description = "Common tags that would be applied"
  value       = local.common_tags
}
