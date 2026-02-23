locals {
  default_tags = {
    ManagedBy = "tofu"
  }
  tags = merge(local.default_tags, var.tags)

  permission_boundary_policy_name = "default-permission-boundary"

  # Identity Center instance (asserts exactly one exists)
  identity_center_instance_arn = one(data.aws_ssoadmin_instances.this.arns)
  identity_store_id            = one(data.aws_ssoadmin_instances.this.identity_store_ids)
}

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_ssoadmin_instances" "this" {}

# -----------------------------------------------------------------------------
# Permission Boundary Policy Document
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "permission_boundary" {
  # Allow all actions (the boundary works by intersection with identity policies)
  statement {
    sid       = "AllowAll"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  # Deny VPC mutations
  statement {
    sid    = "DenyVPCMutations"
    effect = "Deny"
    actions = [
      "ec2:CreateVpc",
      "ec2:DeleteVpc",
      "ec2:CreateSubnet",
      "ec2:DeleteSubnet",
      "ec2:CreateInternetGateway",
      "ec2:DeleteInternetGateway",
      "ec2:AttachInternetGateway",
      "ec2:DetachInternetGateway",
      "ec2:CreateNatGateway",
      "ec2:DeleteNatGateway",
      "ec2:CreateVpcPeeringConnection",
      "ec2:DeleteVpcPeeringConnection",
      "ec2:AcceptVpcPeeringConnection",
      "ec2:CreateTransitGateway",
      "ec2:DeleteTransitGateway",
      "ec2:ModifyVpcAttribute",
    ]
    resources = ["*"]
  }

  # Deny organization actions
  statement {
    sid    = "DenyOrganizationActions"
    effect = "Deny"
    actions = [
      "organizations:LeaveOrganization",
      "organizations:DeleteOrganization",
      "organizations:RemoveAccountFromOrganization",
      "organizations:CreateAccount",
      "organizations:CloseAccount",
      "organizations:CreateOrganization",
      "organizations:InviteAccountToOrganization",
      "organizations:CreatePolicy",
      "organizations:DeletePolicy",
      "organizations:UpdatePolicy",
      "organizations:AttachPolicy",
      "organizations:DetachPolicy",
    ]
    resources = ["*"]
  }

  # Deny IAM user creation
  statement {
    sid    = "DenyIAMUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:DeleteUser",
    ]
    resources = ["*"]
  }

  # Deny creating roles without permission boundary
  statement {
    sid    = "DenyCreateRoleWithoutBoundary"
    effect = "Deny"
    actions = [
      "iam:CreateRole",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotLike"
      variable = "iam:PermissionsBoundary"
      values   = ["arn:aws:iam::*:policy/${local.permission_boundary_policy_name}"]
    }
  }

  # Deny modifying or removing permission boundaries on roles
  statement {
    sid    = "DenyPermissionBoundaryModification"
    effect = "Deny"
    actions = [
      "iam:PutRolePermissionsBoundary",
      "iam:DeleteRolePermissionsBoundary",
    ]
    resources = ["*"]
  }

  # Deny modifying or deleting the permission boundary policy itself
  statement {
    sid    = "DenyPermissionBoundaryPolicyMutation"
    effect = "Deny"
    actions = [
      "iam:CreatePolicyVersion",
      "iam:DeletePolicy",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
    ]
    resources = ["arn:aws:iam::*:policy/${local.permission_boundary_policy_name}"]
  }
}

# -----------------------------------------------------------------------------
# Permission Sets
# -----------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "reader" {
  name             = "Reader"
  description      = "Read-only access across all AWS services"
  instance_arn     = local.identity_center_instance_arn
  session_duration = var.reader_session_duration

  tags = local.tags
}

resource "aws_ssoadmin_permission_set" "operator" {
  name             = "Operator"
  description      = "Near-full admin access with restrictions on dangerous operations"
  instance_arn     = local.identity_center_instance_arn
  session_duration = var.operator_session_duration

  tags = local.tags
}

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "Admin"
  description      = "Full administrative access with no restrictions"
  instance_arn     = local.identity_center_instance_arn
  session_duration = var.admin_session_duration

  tags = local.tags
}

# -----------------------------------------------------------------------------
# Managed Policy Attachments
# -----------------------------------------------------------------------------

resource "aws_ssoadmin_managed_policy_attachment" "reader" {
  instance_arn       = local.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.reader.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ViewOnlyAccess"
}

resource "aws_ssoadmin_managed_policy_attachment" "operator" {
  instance_arn       = local.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.operator.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# Permission Boundary Attachments
# -----------------------------------------------------------------------------

resource "aws_ssoadmin_permissions_boundary_attachment" "reader" {
  instance_arn       = local.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.reader.arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = local.permission_boundary_policy_name
    }
  }
}

resource "aws_ssoadmin_permissions_boundary_attachment" "operator" {
  instance_arn       = local.identity_center_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.operator.arn

  permissions_boundary {
    customer_managed_policy_reference {
      name = local.permission_boundary_policy_name
    }
  }
}
