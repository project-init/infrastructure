#------------------------------------------------------------------------------
# Override Tests
# Tests the shared_pool_cidr_override and external_pool_cidr_override functionality
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Test: Shared pool override is used when provided
#------------------------------------------------------------------------------
run "shared_pool_override_used" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions            = ["us-east-1"]
    shared_pool_cidr_override = "10.128.0.0/12"
  }

  assert {
    condition     = output.using_shared_override == true
    error_message = "Should detect shared override is being used"
  }

  assert {
    condition     = output.shared_pool_cidr == "10.128.0.0/12"
    error_message = "Shared pool should use the override value, got ${output.shared_pool_cidr}"
  }

  # External should still use top-down (highest available after override is excluded)
  assert {
    condition     = output.external_pool_cidr == "10.240.0.0/12"
    error_message = "External pool should still be 10.240.0.0/12, got ${output.external_pool_cidr}"
  }

  # Override CIDR should be excluded from available pool
  assert {
    condition     = !contains(output.available_cidrs, "10.128.0.0/12")
    error_message = "Override CIDR should be excluded from available_cidrs"
  }
}

#------------------------------------------------------------------------------
# Test: External pool override is used when provided
#------------------------------------------------------------------------------
run "external_pool_override_used" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions              = ["us-east-1"]
    external_pool_cidr_override = "10.64.0.0/12"
  }

  assert {
    condition     = output.using_external_override == true
    error_message = "Should detect external override is being used"
  }

  assert {
    condition     = output.external_pool_cidr == "10.64.0.0/12"
    error_message = "External pool should use the override value, got ${output.external_pool_cidr}"
  }

  # When external is overridden, shared gets the highest available
  assert {
    condition     = output.shared_pool_cidr == "10.240.0.0/12"
    error_message = "Shared pool should be 10.240.0.0/12 (highest available), got ${output.shared_pool_cidr}"
  }

  # Override CIDR should be excluded from available pool
  assert {
    condition     = !contains(output.available_cidrs, "10.64.0.0/12")
    error_message = "Override CIDR should be excluded from available_cidrs"
  }
}

#------------------------------------------------------------------------------
# Test: Both overrides used together
#------------------------------------------------------------------------------
run "both_overrides_used" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions              = ["us-east-1", "us-west-2"]
    shared_pool_cidr_override   = "10.96.0.0/12"
    external_pool_cidr_override = "10.112.0.0/12"
  }

  assert {
    condition     = output.using_shared_override == true
    error_message = "Should detect shared override is being used"
  }

  assert {
    condition     = output.using_external_override == true
    error_message = "Should detect external override is being used"
  }

  assert {
    condition     = output.shared_pool_cidr == "10.96.0.0/12"
    error_message = "Shared pool should use override, got ${output.shared_pool_cidr}"
  }

  assert {
    condition     = output.external_pool_cidr == "10.112.0.0/12"
    error_message = "External pool should use override, got ${output.external_pool_cidr}"
  }

  # Both overrides should be excluded from available pool
  assert {
    condition     = !contains(output.available_cidrs, "10.96.0.0/12")
    error_message = "Shared override CIDR should be excluded from available_cidrs"
  }

  assert {
    condition     = !contains(output.available_cidrs, "10.112.0.0/12")
    error_message = "External override CIDR should be excluded from available_cidrs"
  }

  # Regional assignments should still work from lowest available
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.0.0.0/12"
    error_message = "us-east-1 should still get 10.0.0.0/12, got ${output.regional_pool_assignments["us-east-1"]}"
  }

  # Auto-allocated should be 0 when both are overridden
  assert {
    condition     = output.auto_allocated_special_pools == 0
    error_message = "Should have 0 auto-allocated pools when both are overridden, got ${output.auto_allocated_special_pools}"
  }
}

#------------------------------------------------------------------------------
# Test: Override allows more regions (no auto-allocation needed)
#------------------------------------------------------------------------------
run "overrides_increase_region_capacity" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = [
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
      "sa-east-1", "ca-central-1", "af-south-1", "me-south-1"
    ]
    shared_pool_cidr_override   = "10.224.0.0/12"
    external_pool_cidr_override = "10.240.0.0/12"
  }

  # With both overridden, we can use all 16 /12 blocks for regions
  # But overrides take 2, so 14 available for regions
  assert {
    condition     = output.total_available == 14
    error_message = "Should have 14 available blocks (16 - 2 overrides), got ${output.total_available}"
  }

  # Required capacity should equal regions only (no auto-allocation)
  assert {
    condition     = output.required_capacity == 16
    error_message = "Required capacity should be 16 (regions only), got ${output.required_capacity}"
  }

  # This exceeds capacity - validation should flag it
  assert {
    condition     = output.has_sufficient_capacity == false
    error_message = "Should NOT have sufficient capacity for 16 regions with 14 available"
  }
}

#------------------------------------------------------------------------------
# Test: Override with maximum valid regions
#------------------------------------------------------------------------------
run "overrides_with_max_valid_regions" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = [
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
      "sa-east-1", "ca-central-1"
    ]
    shared_pool_cidr_override   = "10.224.0.0/12"
    external_pool_cidr_override = "10.240.0.0/12"
  }

  # 14 regions + 2 overrides = exactly 16
  assert {
    condition     = output.has_sufficient_capacity == true
    error_message = "Should have sufficient capacity for 14 regions with both pools overridden"
  }

  assert {
    condition     = length(output.regional_pool_assignments) == 14
    error_message = "Should have 14 regional assignments, got ${length(output.regional_pool_assignments)}"
  }
}

#------------------------------------------------------------------------------
# Test: Shared override overlaps with legacy - validation fails
#------------------------------------------------------------------------------
run "shared_override_overlaps_legacy_detected" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-datacenter"
        cidr        = "10.48.0.0/12"
        description = "Legacy network"
      }
    ]
    shared_pool_cidr_override = "10.48.0.0/12"
  }

  assert {
    condition     = output.shared_override_overlaps_legacy == true
    error_message = "Should detect shared override overlaps with legacy"
  }

  assert {
    condition     = output.is_valid == false
    error_message = "Configuration should be invalid when shared override overlaps legacy"
  }
}

#------------------------------------------------------------------------------
# Test: External override overlaps with legacy - validation fails
#------------------------------------------------------------------------------
run "external_override_overlaps_legacy_detected" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-datacenter"
        cidr        = "10.64.0.0/12"
        description = "Legacy network"
      }
    ]
    external_pool_cidr_override = "10.64.0.0/12"
  }

  assert {
    condition     = output.external_override_overlaps_legacy == true
    error_message = "Should detect external override overlaps with legacy"
  }

  assert {
    condition     = output.is_valid == false
    error_message = "Configuration should be invalid when external override overlaps legacy"
  }
}

#------------------------------------------------------------------------------
# Test: Shared and external overrides are the same - validation fails
#------------------------------------------------------------------------------
run "same_override_for_both_detected" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions              = ["us-east-1"]
    shared_pool_cidr_override   = "10.128.0.0/12"
    external_pool_cidr_override = "10.128.0.0/12"
  }

  assert {
    condition     = output.overrides_overlap == true
    error_message = "Should detect when both overrides are the same"
  }

  assert {
    condition     = output.is_valid == false
    error_message = "Configuration should be invalid when overrides are the same"
  }
}

#------------------------------------------------------------------------------
# Test: Override at low end of range works
#------------------------------------------------------------------------------
run "override_at_low_end" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions            = ["us-east-1"]
    shared_pool_cidr_override = "10.0.0.0/12"
  }

  assert {
    condition     = output.shared_pool_cidr == "10.0.0.0/12"
    error_message = "Should accept override at 10.0.0.0/12"
  }

  # First region should skip to next available
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.16.0.0/12"
    error_message = "us-east-1 should skip override and get 10.16.0.0/12, got ${output.regional_pool_assignments["us-east-1"]}"
  }
}

#------------------------------------------------------------------------------
# Test: Override at high end of range works
#------------------------------------------------------------------------------
run "override_at_high_end" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions              = ["us-east-1"]
    external_pool_cidr_override = "10.240.0.0/12"
  }

  assert {
    condition     = output.external_pool_cidr == "10.240.0.0/12"
    error_message = "Should accept override at 10.240.0.0/12"
  }

  # Shared should get highest available (10.224.0.0/12 since external took 10.240.0.0/12)
  # But wait - external override means 10.240.0.0/12 is removed from available
  # So shared gets highest from remaining = 10.224.0.0/12
  assert {
    condition     = output.shared_pool_cidr == "10.224.0.0/12"
    error_message = "Shared should get 10.224.0.0/12 (highest available after override), got ${output.shared_pool_cidr}"
  }
}

#------------------------------------------------------------------------------
# Test: Override in middle of range doesn't affect regional bottom-up
#------------------------------------------------------------------------------
run "override_in_middle_no_affect_on_regional" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions              = ["us-east-1", "us-west-2", "eu-west-1"]
    shared_pool_cidr_override   = "10.80.0.0/12"
    external_pool_cidr_override = "10.96.0.0/12"
  }

  # Regional assignments should still be bottom-up from lowest
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.0.0.0/12"
    error_message = "us-east-1 should get 10.0.0.0/12"
  }

  assert {
    condition     = output.regional_pool_assignments["us-west-2"] == "10.16.0.0/12"
    error_message = "us-west-2 should get 10.16.0.0/12"
  }

  assert {
    condition     = output.regional_pool_assignments["eu-west-1"] == "10.32.0.0/12"
    error_message = "eu-west-1 should get 10.32.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: Only one override with legacy allocations
#------------------------------------------------------------------------------
run "single_override_with_legacy" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-1"
        cidr        = "10.240.0.0/12"
        description = "Legacy at top"
      }
    ]
    shared_pool_cidr_override = "10.128.0.0/12"
  }

  # Total available should be 14 (16 - 1 legacy - 1 shared override)
  assert {
    condition     = output.total_available == 14
    error_message = "Should have 14 available (16 - 1 legacy - 1 override), got ${output.total_available}"
  }

  assert {
    condition     = output.shared_pool_cidr == "10.128.0.0/12"
    error_message = "Shared should use override"
  }

  # External should be highest available after legacy exclusion
  # Legacy took 10.240.0.0/12, so highest is 10.224.0.0/12
  assert {
    condition     = output.external_pool_cidr == "10.224.0.0/12"
    error_message = "External should be 10.224.0.0/12 (highest after legacy), got ${output.external_pool_cidr}"
  }
}

#------------------------------------------------------------------------------
# Test: Verify available_cidrs excludes both legacy and overrides
#------------------------------------------------------------------------------
run "available_excludes_legacy_and_overrides" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-1"
        cidr        = "10.32.0.0/12"
        description = "Legacy block"
      }
    ]
    shared_pool_cidr_override   = "10.64.0.0/12"
    external_pool_cidr_override = "10.96.0.0/12"
  }

  # Available should exclude: legacy (10.32.0.0/12), shared override (10.64.0.0/12), external override (10.96.0.0/12)
  assert {
    condition     = !contains(output.available_cidrs, "10.32.0.0/12")
    error_message = "Legacy CIDR should be excluded from available"
  }

  assert {
    condition     = !contains(output.available_cidrs, "10.64.0.0/12")
    error_message = "Shared override CIDR should be excluded from available"
  }

  assert {
    condition     = !contains(output.available_cidrs, "10.96.0.0/12")
    error_message = "External override CIDR should be excluded from available"
  }

  # Should have 13 available (16 - 1 legacy - 2 overrides)
  assert {
    condition     = output.total_available == 13
    error_message = "Should have 13 available CIDRs, got ${output.total_available}"
  }
}
