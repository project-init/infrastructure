#------------------------------------------------------------------------------
# Root Zone Outputs
#------------------------------------------------------------------------------
output "root_zone_id" {
  description = "Hosted Zone ID for the root domain."
  value       = aws_route53_zone.root.zone_id
}

output "root_zone_arn" {
  description = "ARN of the root hosted zone."
  value       = aws_route53_zone.root.arn
}

output "root_zone_name_servers" {
  description = "Name servers for the root domain. Configure these at your domain registrar."
  value       = aws_route53_zone.root.name_servers
}

#------------------------------------------------------------------------------
# Environment Zone Outputs
#------------------------------------------------------------------------------
output "env_zone_ids" {
  description = "Map of environment -> zone_id for the created environment subdomains."
  value       = { for env, zone in aws_route53_zone.environment : env => zone.zone_id }
}

output "env_zone_arns" {
  description = "Map of environment -> zone_arn for the created environment subdomains."
  value       = { for env, zone in aws_route53_zone.environment : env => zone.arn }
}

output "env_zone_names" {
  description = "Map of environment -> full_domain_name for the created environment subdomains."
  value       = local.env_domain_names
}

output "env_zone_name_servers" {
  description = "Map of environment -> name_servers for the created environment subdomains."
  value       = { for env, zone in aws_route53_zone.environment : env => zone.name_servers }
}

#------------------------------------------------------------------------------
# Summary Output
#------------------------------------------------------------------------------
output "dns_summary" {
  description = "Summary of DNS configuration for documentation purposes."
  value = {
    root_domain       = var.root_domain
    root_zone_id      = aws_route53_zone.root.zone_id
    root_name_servers = aws_route53_zone.root.name_servers
    environments = {
      for env in var.environments : env => {
        domain       = local.env_domain_names[env]
        zone_id      = aws_route53_zone.environment[env].zone_id
        name_servers = aws_route53_zone.environment[env].name_servers
      }
    }
  }
}
