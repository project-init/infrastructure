locals {
  # System tags are merged AFTER var.tags so they cannot be overridden
  # This ensures PlatformManaged=true is always set for SCP/Permission Boundary protection
  common_tags = merge(
    var.tags,
    {
      PlatformManaged = "true"
      Organization    = var.organization
      Namespace       = var.namespace
      Environment     = var.environment
    }
  )

  reader_role_arn   = "arn:aws:iam::${var.platform_account_id}:role/platform-reader-admin"
  deployer_role_arn = "arn:aws:iam::${var.platform_account_id}:role/platform-deployer-admin"
}

# -----------------------------------------------------------------------------
# Trust Policy
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  # Reader role can assume but cannot tag sessions (prevents privilege escalation)
  statement {
    sid     = "AllowPlatformReaderAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "AWS"
      identifiers = [local.reader_role_arn]
    }
  }

  # Deployer role can assume and tag sessions, but tags are constrained
  # to prevent arbitrary tag injection
  statement {
    sid     = "AllowPlatformDeployerAssumeRoleWithTags"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = [local.deployer_role_arn]
    }

    # If the Role tag is requested, it must be "Deployer"
    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Role"
      values   = ["Deployer"]
    }

    # Restrict session tag keys to Role only
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Role"]
    }
  }
}

# -----------------------------------------------------------------------------
# Platform Execution Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "platform_execution" {
  name               = "platform-execution"
  assume_role_policy = data.aws_iam_policy_document.trust.json
  tags               = local.common_tags
}

# -----------------------------------------------------------------------------
# ReadOnly Access (Managed Policy Attachment)
# -----------------------------------------------------------------------------

resource "aws_iam_role_policy_attachment" "readonly" {
  role       = aws_iam_role.platform_execution.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# -----------------------------------------------------------------------------
# Conditional Administrator Access (Inline Policy)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "admin_access" {
  statement {
    sid       = "ConditionalAdminAccess"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/Role"
      values   = ["Deployer"]
    }
  }
}

resource "aws_iam_role_policy" "admin_access" {
  name   = "platform-execution-admin-access"
  role   = aws_iam_role.platform_execution.name
  policy = data.aws_iam_policy_document.admin_access.json
}
