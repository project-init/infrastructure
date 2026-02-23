output "role_arn" {
  description = "The ARN of the IAM role"
  value       = aws_iam_role.this.arn
}

output "role_name" {
  description = "The name of the IAM role"
  value       = aws_iam_role.this.name
}

output "role_id" {
  description = "The unique ID of the IAM role"
  value       = aws_iam_role.this.unique_id
}

output "instance_profile_arn" {
  description = "The ARN of the instance profile (null if is_instance_role = false)"
  value       = var.is_instance_role ? aws_iam_instance_profile.this[0].arn : null
}

output "instance_profile_name" {
  description = "The name of the instance profile (null if is_instance_role = false)"
  value       = var.is_instance_role ? aws_iam_instance_profile.this[0].name : null
}
