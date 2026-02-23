resource "aws_organizations_account" "this" {
  name      = "${var.namespace}-${var.environment}"
  email     = var.email
  role_name = var.role_name
  parent_id = var.parent_id

  tags = merge(
    {
      Organization = var.organization
      Namespace    = var.namespace
      Environment  = var.environment
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [role_name]
  }
}
