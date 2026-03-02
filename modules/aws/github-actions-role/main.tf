data "aws_caller_identity" "current" {}

locals {
  default_oidc_provider_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
  oidc_provider_arn         = var.oidc_provider_arn != "" ? var.oidc_provider_arn : local.default_oidc_provider_arn
}

data "aws_iam_policy_document" "trust" {
  dynamic "statement" {
    for_each = var.authorization_patterns

    content {
      sid     = statement.value.sid
      effect  = "Allow"
      actions = ["sts:AssumeRoleWithWebIdentity"]

      principals {
        type        = "Federated"
        identifiers = [local.oidc_provider_arn]
      }

      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      }

      condition {
        test     = "StringLike"
        variable = "token.actions.githubusercontent.com:sub"
        values   = [for repo in statement.value.claims.repositories : "repo:${repo}:*"]
      }

      dynamic "condition" {
        for_each = length(statement.value.claims.repositories) > 0 ? [statement.value.claims.repositories] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "token.actions.githubusercontent.com:repository"
          values   = condition.value
        }
      }

      dynamic "condition" {
        for_each = statement.value.claims.repository_owners != null ? [statement.value.claims.repository_owners] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "token.actions.githubusercontent.com:repository_owner"
          values   = condition.value
        }
      }

      dynamic "condition" {
        for_each = statement.value.claims.refs != null ? [statement.value.claims.refs] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "token.actions.githubusercontent.com:ref"
          values   = condition.value
        }
      }

      dynamic "condition" {
        for_each = statement.value.claims.environments != null ? [statement.value.claims.environments] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "token.actions.githubusercontent.com:environment"
          values   = condition.value
        }
      }

      dynamic "condition" {
        for_each = statement.value.claims.job_workflow_refs != null ? [statement.value.claims.job_workflow_refs] : []
        content {
          test     = "ForAnyValue:StringLike"
          variable = "token.actions.githubusercontent.com:job_workflow_ref"
          values   = condition.value
        }
      }
    }
  }
}

module "iam_role" {
  source = "../iam-role"

  name                = var.name
  name_prefix         = var.name_prefix
  description         = var.description
  assume_role_policy  = data.aws_iam_policy_document.trust.json
  inline_policies     = var.inline_policies
  managed_policy_arns = var.managed_policy_arns
  tags                = var.tags
}