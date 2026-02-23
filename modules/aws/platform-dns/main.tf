#------------------------------------------------------------------------------
# Platform DNS Module
# Manages Route53 Hosted Zones for the Root Domain and Environment subdomains
# in the Platform Account. Handles internal delegation from Root to Environments.
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Local Variables
#------------------------------------------------------------------------------
locals {
  # Common tags for all resources
  common_tags = merge(
    {
      Module  = "platform-dns"
      Purpose = "DNS Management"
    },
    var.tags
  )

  # Create a map of environment -> full domain name for easier reference
  env_domain_names = {
    for env in var.environments : env => "${env}.${var.root_domain}"
  }
}

#------------------------------------------------------------------------------
# Root Hosted Zone
#------------------------------------------------------------------------------
resource "aws_route53_zone" "root" {
  name    = var.root_domain
  comment = "Managed by Platform DNS Module"

  tags = merge(local.common_tags, {
    Name = var.root_domain
    Type = "root"
  })
}

#------------------------------------------------------------------------------
# Environment Hosted Zones
#------------------------------------------------------------------------------
resource "aws_route53_zone" "environment" {
  for_each = toset(var.environments)

  name    = local.env_domain_names[each.key]
  comment = "Environment Subdomain for ${each.key}"

  tags = merge(local.common_tags, {
    Name        = local.env_domain_names[each.key]
    Type        = "environment"
    Environment = each.key
  })
}

#------------------------------------------------------------------------------
# NS Delegation Records (Root -> Environment)
# These records in the root zone delegate authority for each environment
# subdomain to the respective environment hosted zone.
#------------------------------------------------------------------------------
resource "aws_route53_record" "environment_delegation" {
  for_each = toset(var.environments)

  zone_id = aws_route53_zone.root.zone_id
  name    = local.env_domain_names[each.key]
  type    = "NS"
  ttl     = 3600 # 1 hour - common for NS records

  records = aws_route53_zone.environment[each.key].name_servers
}
