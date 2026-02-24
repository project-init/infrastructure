output "identity_center_instance_arn" {
  description = "ARN of the IAM Identity Center instance"
  value       = local.identity_center_instance_arn
}

output "identity_store_id" {
  description = "ID of the Identity Store associated with Identity Center"
  value       = local.identity_store_id
}

output "permission_set_arns" {
  description = "Map of permission set names to their ARNs"
  value = {
    "Reader"   = aws_ssoadmin_permission_set.reader.arn
    "Operator" = aws_ssoadmin_permission_set.operator.arn
    "Admin"    = aws_ssoadmin_permission_set.admin.arn
  }
}

output "permission_boundary_policy_document" {
  description = "JSON policy document for the permission boundary (to be created in target accounts)"
  value       = data.aws_iam_policy_document.permission_boundary.json
}

output "permission_boundary_policy_name" {
  description = "Expected name for the permission boundary policy (for consistent ARN construction)"
  value       = local.permission_boundary_policy_name
}
