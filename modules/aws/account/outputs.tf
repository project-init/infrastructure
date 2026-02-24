output "account_id" {
  description = "The AWS Account ID of the newly created account."
  value       = aws_organizations_account.this.id
}

output "account_arn" {
  description = "The ARN of the newly created account."
  value       = aws_organizations_account.this.arn
}

output "organization_role_arn" {
  description = "The complete ARN of the bootstrap role."
  value       = "arn:aws:iam::${aws_organizations_account.this.id}:role/${var.role_name}"
}

output "parent_id" {
  description = "The Parent ID the account was placed in."
  value       = aws_organizations_account.this.parent_id
}
