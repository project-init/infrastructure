#------------------------------------------------------------------------------
# Account Bootstrap IAM Module Tests
# Tests the platform-execution role, trust policy, and permissions model
#------------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"MockStatement\",\"Effect\":\"Allow\",\"Action\":\"*\",\"Resource\":\"*\"}]}"
    }
  }
}

#------------------------------------------------------------------------------
# Test: Complete module - role configuration, tagging, and policy attachments
#------------------------------------------------------------------------------
run "platform_execution_role_configuration" {
  command = plan

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "analytics"
    environment         = "production"
    tags = {
      Team    = "Platform"
      Project = "Infrastructure"
    }
  }

  # Role name
  assert {
    condition     = aws_iam_role.platform_execution.name == "platform-execution"
    error_message = "Role name should be 'platform-execution'"
  }

  # Verify all expected tags are present
  assert {
    condition     = aws_iam_role.platform_execution.tags["PlatformManaged"] == "true"
    error_message = "Role should have PlatformManaged=true tag"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Organization"] == "acme"
    error_message = "Role should have Organization tag from variable"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Namespace"] == "analytics"
    error_message = "Role should have Namespace tag from variable"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Environment"] == "production"
    error_message = "Role should have Environment tag from variable"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Team"] == "Platform"
    error_message = "Role should have custom Team tag from var.tags"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Project"] == "Infrastructure"
    error_message = "Role should have custom Project tag from var.tags"
  }

  # ReadOnly policy attachment
  assert {
    condition     = aws_iam_role_policy_attachment.readonly.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "ReadOnly managed policy should be attached"
  }

  assert {
    condition     = aws_iam_role_policy_attachment.readonly.role == "platform-execution"
    error_message = "ReadOnly policy should be attached to platform-execution role"
  }

  # Conditional admin inline policy
  assert {
    condition     = aws_iam_role_policy.admin_access.name == "platform-execution-admin-access"
    error_message = "Admin policy should be named 'platform-execution-admin-access'"
  }

  # Outputs - role_name is known at plan time, role_arn is not (computed by AWS)
  assert {
    condition     = output.role_name == "platform-execution"
    error_message = "role_name output should be 'platform-execution'"
  }
}

#------------------------------------------------------------------------------
# Test: Minimal configuration - only required variables, verify tag count
#------------------------------------------------------------------------------
run "minimal_configuration" {
  command = plan

  variables {
    platform_account_id = "987654321098"
    organization        = "testorg"
    namespace           = "core"
    environment         = "staging"
  }

  # Role should still be created with minimal config
  assert {
    condition     = aws_iam_role.platform_execution.name == "platform-execution"
    error_message = "Role should be created with minimal configuration"
  }

  # All required tags should be present
  assert {
    condition     = aws_iam_role.platform_execution.tags["PlatformManaged"] == "true"
    error_message = "PlatformManaged tag should be present"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Organization"] == "testorg"
    error_message = "Organization tag should match variable"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Namespace"] == "core"
    error_message = "Namespace tag should match variable"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Environment"] == "staging"
    error_message = "Environment tag should match variable"
  }

  # Verify exactly 4 tags when var.tags is empty (default)
  assert {
    condition     = length(aws_iam_role.platform_execution.tags) == 4
    error_message = "Should have exactly 4 tags (PlatformManaged, Organization, Namespace, Environment) when var.tags is empty"
  }

  # Verify all three resources are planned
  assert {
    condition     = aws_iam_role_policy_attachment.readonly.policy_arn == "arn:aws:iam::aws:policy/ReadOnlyAccess"
    error_message = "ReadOnly policy attachment should be planned"
  }

  assert {
    condition     = aws_iam_role_policy.admin_access.name == "platform-execution-admin-access"
    error_message = "Admin inline policy should be planned"
  }
}

#------------------------------------------------------------------------------
# Test: All valid environments work (staging, production, global)
#------------------------------------------------------------------------------
run "valid_environments" {
  command = plan

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "shared"
    environment         = "global"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Environment"] == "global"
    error_message = "Environment 'global' should be accepted"
  }

  assert {
    condition     = aws_iam_role.platform_execution.name == "platform-execution"
    error_message = "Role should be created for global environment"
  }
}

run "staging_environment" {
  command = plan

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "workloads"
    environment         = "staging"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Environment"] == "staging"
    error_message = "Environment 'staging' should be accepted"
  }
}

run "production_environment" {
  command = plan

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "workloads"
    environment         = "production"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Environment"] == "production"
    error_message = "Environment 'production' should be accepted"
  }
}

#------------------------------------------------------------------------------
# Test: Custom tags are merged with system tags
#------------------------------------------------------------------------------
run "custom_tags_merged" {
  command = plan

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "test"
    environment         = "production"
    tags = {
      CostCenter  = "12345"
      Application = "platform-infra"
      ManagedBy   = "terraform"
    }
  }

  # System tags should be present
  assert {
    condition     = aws_iam_role.platform_execution.tags["PlatformManaged"] == "true"
    error_message = "System tag PlatformManaged should be present"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Organization"] == "acme"
    error_message = "System tag Organization should be present"
  }

  # Custom tags should be merged
  assert {
    condition     = aws_iam_role.platform_execution.tags["CostCenter"] == "12345"
    error_message = "Custom tag CostCenter should be merged"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["Application"] == "platform-infra"
    error_message = "Custom tag Application should be merged"
  }

  assert {
    condition     = aws_iam_role.platform_execution.tags["ManagedBy"] == "terraform"
    error_message = "Custom tag ManagedBy should be merged"
  }

  # Total should be 7 tags (4 system + 3 custom)
  assert {
    condition     = length(aws_iam_role.platform_execution.tags) == 7
    error_message = "Should have 7 total tags (4 system + 3 custom)"
  }
}
