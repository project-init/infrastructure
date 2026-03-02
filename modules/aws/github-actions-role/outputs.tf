output "role_arn" {
  description = "The ARN of the created IAM role."
  value       = module.iam_role.role_arn
}

output "role_name" {
  description = "The name of the created IAM role."
  value       = module.iam_role.role_name
}