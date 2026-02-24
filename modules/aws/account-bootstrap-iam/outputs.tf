output "role_arn" {
  description = "ARN of the platform-execution role."
  value       = aws_iam_role.platform_execution.arn
}

output "role_name" {
  description = "Name of the platform-execution role."
  value       = aws_iam_role.platform_execution.name
}
