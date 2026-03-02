data "aws_iam_policy" "permission_boundary" {
  name = var.permission_boundary_name
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  effective_assume_role_policy = var.assume_role_policy != null ? var.assume_role_policy : (
    var.is_instance_role ? data.aws_iam_policy_document.ec2_trust.json : null
  )

  merged_tags = merge(
    {
      ManagedBy = "tofu"
    },
    var.tags
  )

  inline_policies_map = { for p in var.inline_policies : p.name => p.policy }
}

resource "aws_iam_role" "this" {
  name                  = var.name
  name_prefix           = var.name_prefix
  description           = var.description
  assume_role_policy    = local.effective_assume_role_policy
  permissions_boundary  = data.aws_iam_policy.permission_boundary.arn
  max_session_duration  = var.max_session_duration
  path                  = var.path
  force_detach_policies = var.force_detach_policies
  tags                  = local.merged_tags
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

  name        = var.name
  name_prefix = var.name_prefix
  path        = var.path
  role        = aws_iam_role.this.name
  tags        = local.merged_tags
}
