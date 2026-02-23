output "reader_role_arn" {
  description = "ARN of platform-reader-admin"
  value       = aws_iam_role.reader.arn
}

output "deployer_role_arn" {
  description = "ARN of platform-deployer-admin"
  value       = aws_iam_role.deployer.arn
}
