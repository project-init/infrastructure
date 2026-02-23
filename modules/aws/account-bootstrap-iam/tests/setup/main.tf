#------------------------------------------------------------------------------
# Test Setup Module
# Exposes the policy document logic for unit testing without AWS resources
#------------------------------------------------------------------------------

variable "platform_account_id" {
  type = string
}

variable "organization" {
  type = string
}

variable "namespace" {
  type = string
}

variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  reader_role_arn   = "arn:aws:iam::${var.platform_account_id}:role/platform-reader-admin"
  deployer_role_arn = "arn:aws:iam::${var.platform_account_id}:role/platform-deployer-admin"

  # System tags are merged AFTER var.tags so they cannot be overridden
  common_tags = merge(
    var.tags,
    {
      PlatformManaged = "true"
      Organization    = var.organization
      Namespace       = var.namespace
      Environment     = var.environment
    }
  )

  # Trust policy structure - split into reader and deployer statements
  # Reader: can assume but NOT tag sessions (prevents privilege escalation)
  # Deployer: can assume and tag sessions with constrained tags
  trust_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPlatformReaderAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = local.reader_role_arn
        }
        Action = "sts:AssumeRole"
      },
      {
        Sid    = "AllowPlatformDeployerAssumeRoleWithTags"
        Effect = "Allow"
        Principal = {
          AWS = local.deployer_role_arn
        }
        Action = ["sts:AssumeRole", "sts:TagSession"]
        Condition = {
          StringEquals = {
            "aws:RequestTag/Role" = "Deployer"
          }
          "ForAllValues:StringEquals" = {
            "aws:TagKeys" = ["Role"]
          }
        }
      }
    ]
  }

  # Admin access policy structure (what the data source would produce)
  admin_access_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ConditionalAdminAccess"
        Effect   = "Allow"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:PrincipalTag/Role" = "Deployer"
          }
        }
      }
    ]
  }

  # Derived values for testing
  reader_trust_actions   = local.trust_policy.Statement[0].Action
  deployer_trust_actions = local.trust_policy.Statement[1].Action
  admin_condition_key    = keys(local.admin_access_policy.Statement[0].Condition.StringEquals)[0]
  admin_condition_value  = local.admin_access_policy.Statement[0].Condition.StringEquals["aws:PrincipalTag/Role"]

  # Deployer tag constraints
  deployer_required_tag_value = local.trust_policy.Statement[1].Condition.StringEquals["aws:RequestTag/Role"]
  deployer_allowed_tag_keys   = local.trust_policy.Statement[1].Condition["ForAllValues:StringEquals"]["aws:TagKeys"]
}

output "reader_role_arn" {
  value = local.reader_role_arn
}

output "deployer_role_arn" {
  value = local.deployer_role_arn
}

output "reader_trust_actions" {
  description = "Actions allowed for reader in trust policy"
  value       = local.reader_trust_actions
}

output "deployer_trust_actions" {
  description = "Actions allowed for deployer in trust policy"
  value       = local.deployer_trust_actions
}

output "deployer_required_tag_value" {
  description = "Required value for Role tag when deployer assumes role"
  value       = local.deployer_required_tag_value
}

output "deployer_allowed_tag_keys" {
  description = "Allowed tag keys for deployer session tagging"
  value       = local.deployer_allowed_tag_keys
}

output "common_tags" {
  value = local.common_tags
}

output "tag_count" {
  value = length(local.common_tags)
}

output "admin_condition_key" {
  value = local.admin_condition_key
}

output "admin_condition_value" {
  value = local.admin_condition_value
}

output "trust_policy_json" {
  value = jsonencode(local.trust_policy)
}

output "admin_access_policy_json" {
  value = jsonencode(local.admin_access_policy)
}
