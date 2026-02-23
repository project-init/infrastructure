#------------------------------------------------------------------------------
# Platform DNS Module Tests
# Consolidated tests for validation and output structure
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Test: Valid configuration - domain, environments, outputs, tags
#------------------------------------------------------------------------------
run "valid_configuration" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "example.com"
    environments = ["staging", "production"]
    tags = {
      Team = "Platform"
    }
  }

  # Domain validation
  assert {
    condition     = output.is_valid_root_domain == true
    error_message = "example.com should pass all domain validations"
  }

  # Environment validation
  assert {
    condition     = output.is_valid_environments == true
    error_message = "Environments should pass all validations"
  }

  # Overall validity
  assert {
    condition     = output.is_valid == true
    error_message = "Configuration should be valid"
  }

  # Domain name construction
  assert {
    condition     = output.env_domain_names["staging"] == "staging.example.com"
    error_message = "Staging domain should be staging.example.com"
  }

  assert {
    condition     = output.env_domain_names["production"] == "production.example.com"
    error_message = "Production domain should be production.example.com"
  }

  # Resource counts (1 root + 2 envs = 3 zones, 2 delegation records)
  assert {
    condition     = output.expected_zone_count == 3
    error_message = "Expected 3 zones (1 root + 2 envs)"
  }

  assert {
    condition     = output.expected_delegation_record_count == 2
    error_message = "Expected 2 delegation records"
  }

  # Tags merged correctly
  assert {
    condition     = output.common_tags["Module"] == "platform-dns" && output.common_tags["Team"] == "Platform"
    error_message = "Tags should include default Module and custom Team"
  }

  # Mock outputs have expected format
  assert {
    condition     = startswith(output.mock_root_zone_id, "Z") && length(output.mock_root_name_servers) == 4
    error_message = "Mock zone ID should start with Z, should have 4 name servers"
  }
}

#------------------------------------------------------------------------------
# Test: Invalid root domains - uppercase, dots, single label
#------------------------------------------------------------------------------
run "invalid_root_domains" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "Example.COM"
    environments = ["staging"]
  }

  # Uppercase fails
  assert {
    condition     = output.is_lowercase == false
    error_message = "Uppercase domain should fail lowercase check"
  }

  assert {
    condition     = output.is_valid_root_domain == false
    error_message = "Uppercase domain should fail overall validation"
  }
}

run "leading_trailing_dots_fail" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = ".example.com"
    environments = ["staging"]
  }

  assert {
    condition     = output.no_leading_dot == false && output.is_valid_root_domain == false
    error_message = "Leading dot should fail validation"
  }
}

run "single_label_domain_fails" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "localhost"
    environments = ["staging"]
  }

  assert {
    condition     = output.is_valid_domain_format == false && output.is_valid_root_domain == false
    error_message = "Single label domain (no TLD) should fail"
  }
}

#------------------------------------------------------------------------------
# Test: Invalid environments - uppercase, hyphens, duplicates, empty
#------------------------------------------------------------------------------
run "invalid_environments" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "example.com"
    environments = ["Staging", "-invalid", "staging-"]
  }

  assert {
    condition     = output.environments_are_valid_labels == false
    error_message = "Uppercase and invalid hyphen placement should fail"
  }

  assert {
    condition     = output.is_valid_environments == false
    error_message = "Invalid environments should fail overall"
  }
}

run "duplicate_environments_fail" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "example.com"
    environments = ["staging", "production", "staging"]
  }

  assert {
    condition     = output.environments_are_unique == false && output.is_valid_environments == false
    error_message = "Duplicate environments should fail uniqueness check"
  }
}

run "empty_environments_fail" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "example.com"
    environments = []
  }

  assert {
    condition     = output.has_environments == false && output.is_valid_environments == false
    error_message = "Empty environments should fail"
  }
}

#------------------------------------------------------------------------------
# Test: Complex valid configurations
#------------------------------------------------------------------------------
run "complex_subdomain_root" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "infra.platform.example.com"
    environments = ["dev", "staging", "prod"]
  }

  assert {
    condition     = output.is_valid == true
    error_message = "Complex subdomain as root should be valid"
  }

  assert {
    condition     = output.env_domain_names["dev"] == "dev.infra.platform.example.com"
    error_message = "Dev domain should prepend to complex root"
  }

  assert {
    condition     = output.expected_zone_count == 4 && output.expected_delegation_record_count == 3
    error_message = "Should have 4 zones and 3 delegation records"
  }
}

run "special_valid_formats" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    root_domain  = "my-company123.example.com"
    environments = ["pre-prod", "env1", "a"]
  }

  assert {
    condition     = output.is_valid == true
    error_message = "Hyphens, numbers, and single chars should all be valid"
  }

  assert {
    condition     = output.env_domain_names["pre-prod"] == "pre-prod.my-company123.example.com"
    error_message = "Hyphenated env should work with hyphenated domain"
  }
}
