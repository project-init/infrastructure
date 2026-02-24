data "aws_iam_policy" "permission_boundary" {
  name = var.permission_boundary_name
}

locals {
  ec2_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  effective_assume_role_policy = var.assume_role_policy != null ? var.assume_role_policy : (
    var.is_instance_role ? local.ec2_trust_policy : null
  )

  merged_tags = merge(
    {
      ManagedBy = "tofu"
    },
    var.tags
  )

  inline_policies_map = { for p in var.inline_policies : p.name => p.policy }
}

resource "terraform_data" "validate_assume_role_policy" {
  lifecycle {
    precondition {
      condition     = var.assume_role_policy != null || var.is_instance_role
      error_message = "assume_role_policy is required when is_instance_role is false"
    }
  }
}

resource "aws_iam_role" "this" {
  name                  = var.name
  description           = var.description
  assume_role_policy    = local.effective_assume_role_policy
  permissions_boundary  = data.aws_iam_policy.permission_boundary.arn
  max_session_duration  = var.max_session_duration
  path                  = var.path
  force_detach_policies = var.force_detach_policies
  tags                  = local.merged_tags

  depends_on = [terraform_data.validate_assume_role_policy]
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.inline_policies_map

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}

resource "aws_iam_instance_profile" "this" {
  count = var.is_instance_role ? 1 : 0

  name = var.name
  path = var.path
  role = aws_iam_role.this.name
  tags = local.merged_tags
}
