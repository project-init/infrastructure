locals {
  common_tags = merge(
    {
      PlatformManaged = "true"
    },
    var.tags
  )
}

# -----------------------------------------------------------------------------
# Platform Reader Admin Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "reader_trust" {
  statement {
    sid     = "AllowAssumeRoleWithTagSession"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = var.allowed_principals
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Role"
      values   = ["Reader"]
    }
  }
}

data "aws_iam_policy_document" "reader_permissions" {
  statement {
    sid       = "AllowAssumeExecutionRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:aws:iam::*:role/platform-execution"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Role"
      values   = ["Reader"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/Role"
      values   = ["Reader"]
    }
  }
}

resource "aws_iam_role" "reader" {
  name               = "platform-reader-admin"
  assume_role_policy = data.aws_iam_policy_document.reader_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "reader" {
  name   = "platform-execution-assume"
  role   = aws_iam_role.reader.id
  policy = data.aws_iam_policy_document.reader_permissions.json
}

# -----------------------------------------------------------------------------
# Platform Deployer Admin Role
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "deployer_trust" {
  statement {
    sid     = "AllowAssumeRoleWithTagSession"
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "AWS"
      identifiers = var.allowed_principals
    }

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Role"
      values   = ["Deployer"]
    }
  }
}

data "aws_iam_policy_document" "deployer_permissions" {
  statement {
    sid       = "AllowAssumeExecutionRole"
    effect    = "Allow"
    actions   = ["sts:AssumeRole", "sts:TagSession"]
    resources = ["arn:aws:iam::*:role/platform-execution"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestTag/Role"
      values   = ["Deployer"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalTag/Role"
      values   = ["Deployer"]
    }
  }
}

resource "aws_iam_role" "deployer" {
  name               = "platform-deployer-admin"
  assume_role_policy = data.aws_iam_policy_document.deployer_trust.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy" "deployer" {
  name   = "platform-execution-assume"
  role   = aws_iam_role.deployer.id
  policy = data.aws_iam_policy_document.deployer_permissions.json
}
