#------------------------------------------------------------------------------
# GitHub Actions Role Module Tests
#------------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:user/test-user"
      user_id    = "AROA1234567890"
    }
  }

  mock_data "aws_iam_policy" {
    defaults = {
      arn = "arn:aws:iam::123456789012:policy/default-permission-boundary"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{}"
    }
  }
}

run "valid_configuration_with_name" {
  command = plan

  variables {
    name        = "github-actions-test-role"
    description = "Test role for GitHub Actions"

    authorization_patterns = [
      {
        sid = "AllowMainBranchDeploy"
        claims = {
          repositories = ["my-org/my-repo"]
          refs         = ["refs/heads/main"]
          environments = ["production"]
        }
      }
    ]
  }

  assert {
    condition     = module.iam_role.role_name == "github-actions-test-role"
    error_message = "Role name should match the provided name."
  }
}

run "valid_configuration_with_name_prefix" {
  command = plan

  variables {
    name_prefix = "github-actions-test-"
    description = "Test role with prefix"

    authorization_patterns = [
      {
        sid = "AllowPR"
        claims = {
          repositories = ["my-org/my-repo"]
        }
      }
    ]
  }
}

run "custom_oidc_provider" {
  command = plan

  override_data {
    target = data.aws_caller_identity.current
    values = {
      account_id = "123456789012"
    }
  }

  override_data {
    target = module.iam_role.data.aws_iam_policy.permission_boundary
    values = {
      arn = "arn:aws:iam::123456789012:policy/default-permission-boundary"
    }
  }

  variables {
    name              = "custom-oidc-role"
    description       = "Role with custom OIDC provider"
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/custom.githubusercontent.com"

    authorization_patterns = [
      {
        sid = "AllowAll"
        claims = {
          repositories = ["*"]
        }
      }
    ]
  }
}
