#------------------------------------------------------------------------------
# Policy Logic Tests
# Tests the trust policy and admin policy structures without AWS provider
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Test: Trust policy - reader vs deployer permissions and privilege escalation prevention
#------------------------------------------------------------------------------
run "trust_policy_security_model" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "analytics"
    environment         = "production"
  }

  # Verify reader role ARN is constructed correctly
  assert {
    condition     = output.reader_role_arn == "arn:aws:iam::123456789012:role/platform-reader-admin"
    error_message = "Reader role ARN should be constructed from platform_account_id"
  }

  # Verify deployer role ARN is constructed correctly
  assert {
    condition     = output.deployer_role_arn == "arn:aws:iam::123456789012:role/platform-deployer-admin"
    error_message = "Deployer role ARN should be constructed from platform_account_id"
  }

  # CRITICAL: Reader can only AssumeRole, NOT TagSession (prevents privilege escalation)
  assert {
    condition     = output.reader_trust_actions == "sts:AssumeRole"
    error_message = "Reader should only be allowed sts:AssumeRole (not TagSession) to prevent privilege escalation"
  }

  # Deployer can AssumeRole AND TagSession
  assert {
    condition     = contains(output.deployer_trust_actions, "sts:AssumeRole")
    error_message = "Deployer should be allowed sts:AssumeRole"
  }

  assert {
    condition     = contains(output.deployer_trust_actions, "sts:TagSession")
    error_message = "Deployer should be allowed sts:TagSession"
  }

  # Deployer's session tags are constrained
  assert {
    condition     = output.deployer_required_tag_value == "Deployer"
    error_message = "Deployer must pass Role=Deployer tag when assuming role"
  }

  assert {
    condition     = contains(output.deployer_allowed_tag_keys, "Role")
    error_message = "Deployer can only pass 'Role' tag key"
  }

  assert {
    condition     = length(output.deployer_allowed_tag_keys) == 1
    error_message = "Deployer should only be allowed to pass one tag key (Role)"
  }
}

#------------------------------------------------------------------------------
# Test: Admin policy has correct conditional access
#------------------------------------------------------------------------------
run "admin_policy_condition" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "analytics"
    environment         = "production"
  }

  # Verify the condition checks the correct tag
  assert {
    condition     = output.admin_condition_key == "aws:PrincipalTag/Role"
    error_message = "Admin policy condition should check aws:PrincipalTag/Role"
  }

  # Verify the condition requires Deployer value
  assert {
    condition     = output.admin_condition_value == "Deployer"
    error_message = "Admin policy condition should require 'Deployer' value"
  }

  # Verify policy JSON contains the key elements
  assert {
    condition     = can(regex("ConditionalAdminAccess", output.admin_access_policy_json))
    error_message = "Admin policy should have ConditionalAdminAccess statement ID"
  }

  assert {
    condition     = can(regex("StringEquals", output.admin_access_policy_json))
    error_message = "Admin policy should use StringEquals condition"
  }
}

#------------------------------------------------------------------------------
# Test: Different platform account IDs generate correct ARNs
#------------------------------------------------------------------------------
run "different_platform_account" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    platform_account_id = "999888777666"
    organization        = "other"
    namespace           = "test"
    environment         = "staging"
  }

  assert {
    condition     = output.reader_role_arn == "arn:aws:iam::999888777666:role/platform-reader-admin"
    error_message = "Reader role ARN should use the provided account ID"
  }

  assert {
    condition     = output.deployer_role_arn == "arn:aws:iam::999888777666:role/platform-deployer-admin"
    error_message = "Deployer role ARN should use the provided account ID"
  }

  assert {
    condition     = can(regex("999888777666", output.trust_policy_json))
    error_message = "Trust policy JSON should contain the platform account ID"
  }
}

#------------------------------------------------------------------------------
# Test: System tags cannot be overridden by var.tags (security critical)
#------------------------------------------------------------------------------
run "system_tags_cannot_be_overridden" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "test"
    environment         = "production"
    tags = {
      PlatformManaged = "false"
      Organization    = "attacker-override"
      CustomTag       = "custom-value"
    }
  }

  # CRITICAL: PlatformManaged must always be "true" regardless of var.tags
  assert {
    condition     = output.common_tags["PlatformManaged"] == "true"
    error_message = "PlatformManaged tag must not be overridable (critical for SCP protection)"
  }

  # CRITICAL: Organization must come from var.organization, not var.tags
  assert {
    condition     = output.common_tags["Organization"] == "acme"
    error_message = "Organization tag must not be overridable by var.tags"
  }

  # Custom tags should still be present
  assert {
    condition     = output.common_tags["CustomTag"] == "custom-value"
    error_message = "Custom tags should still be applied"
  }

  # Total count: 4 system + 1 custom (PlatformManaged and Organization from var.tags are overwritten)
  assert {
    condition     = output.tag_count == 5
    error_message = "Should have 5 total tags (4 system + 1 unique custom)"
  }
}

#------------------------------------------------------------------------------
# Test: Tag merging with non-conflicting custom tags
#------------------------------------------------------------------------------
run "custom_tags_merged" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    platform_account_id = "123456789012"
    organization        = "acme"
    namespace           = "test"
    environment         = "production"
    tags = {
      Team       = "Platform"
      CostCenter = "12345"
    }
  }

  # System tags should be present
  assert {
    condition     = output.common_tags["PlatformManaged"] == "true"
    error_message = "PlatformManaged system tag should be present"
  }

  assert {
    condition     = output.common_tags["Organization"] == "acme"
    error_message = "Organization system tag should match variable"
  }

  assert {
    condition     = output.common_tags["Namespace"] == "test"
    error_message = "Namespace system tag should match variable"
  }

  assert {
    condition     = output.common_tags["Environment"] == "production"
    error_message = "Environment system tag should match variable"
  }

  # Custom tags should be merged
  assert {
    condition     = output.common_tags["Team"] == "Platform"
    error_message = "Custom Team tag should be merged"
  }

  assert {
    condition     = output.common_tags["CostCenter"] == "12345"
    error_message = "Custom CostCenter tag should be merged"
  }

  # Total count: 4 system + 2 custom = 6
  assert {
    condition     = output.tag_count == 6
    error_message = "Should have 6 total tags (4 system + 2 custom)"
  }
}
