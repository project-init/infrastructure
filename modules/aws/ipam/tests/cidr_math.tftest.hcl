#------------------------------------------------------------------------------
# CIDR Math Unit Tests
# Tests the core CIDR calculation logic without provisioning AWS resources
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Test: Verify all 16 /12 CIDRs are generated correctly
#------------------------------------------------------------------------------
run "verify_all_slash12_cidrs_generated" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
  }

  assert {
    condition     = length(output.all_slash12_cidrs) == 16
    error_message = "Expected 16 /12 CIDRs, got ${length(output.all_slash12_cidrs)}"
  }

  assert {
    condition     = output.all_slash12_cidrs[0] == "10.0.0.0/12"
    error_message = "First CIDR should be 10.0.0.0/12, got ${output.all_slash12_cidrs[0]}"
  }

  assert {
    condition     = output.all_slash12_cidrs[1] == "10.16.0.0/12"
    error_message = "Second CIDR should be 10.16.0.0/12, got ${output.all_slash12_cidrs[1]}"
  }

  assert {
    condition     = output.all_slash12_cidrs[15] == "10.240.0.0/12"
    error_message = "Last CIDR should be 10.240.0.0/12, got ${output.all_slash12_cidrs[15]}"
  }

  assert {
    condition     = output.all_slash12_cidrs[14] == "10.224.0.0/12"
    error_message = "Second-to-last CIDR should be 10.224.0.0/12, got ${output.all_slash12_cidrs[14]}"
  }
}

#------------------------------------------------------------------------------
# Test: Single region allocation (bottom-up)
#------------------------------------------------------------------------------
run "single_region_bottom_up_allocation" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
  }

  # us-east-1 should get the first (lowest) available CIDR
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.0.0.0/12"
    error_message = "us-east-1 should be assigned 10.0.0.0/12 (bottom-up), got ${output.regional_pool_assignments["us-east-1"]}"
  }

  # Shared pool should get second-highest (10.224.0.0/12)
  assert {
    condition     = output.shared_pool_cidr == "10.224.0.0/12"
    error_message = "Shared pool should be 10.224.0.0/12, got ${output.shared_pool_cidr}"
  }

  # External pool should get highest (10.240.0.0/12)
  assert {
    condition     = output.external_pool_cidr == "10.240.0.0/12"
    error_message = "External pool should be 10.240.0.0/12, got ${output.external_pool_cidr}"
  }

  # Capacity check
  assert {
    condition     = output.required_capacity == 3
    error_message = "Required capacity should be 3 (1 region + 2), got ${output.required_capacity}"
  }

  assert {
    condition     = output.total_available == 16
    error_message = "Total available should be 16, got ${output.total_available}"
  }

  assert {
    condition     = output.has_sufficient_capacity == true
    error_message = "Should have sufficient capacity"
  }
}

#------------------------------------------------------------------------------
# Test: Multiple regions allocation (bottom-up order)
#------------------------------------------------------------------------------
run "multiple_regions_bottom_up_allocation" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1", "us-west-2", "eu-west-1", "ap-southeast-1"]
  }

  # Regions should be assigned in bottom-up order
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.0.0.0/12"
    error_message = "us-east-1 should be 10.0.0.0/12, got ${output.regional_pool_assignments["us-east-1"]}"
  }

  assert {
    condition     = output.regional_pool_assignments["us-west-2"] == "10.16.0.0/12"
    error_message = "us-west-2 should be 10.16.0.0/12, got ${output.regional_pool_assignments["us-west-2"]}"
  }

  assert {
    condition     = output.regional_pool_assignments["eu-west-1"] == "10.32.0.0/12"
    error_message = "eu-west-1 should be 10.32.0.0/12, got ${output.regional_pool_assignments["eu-west-1"]}"
  }

  assert {
    condition     = output.regional_pool_assignments["ap-southeast-1"] == "10.48.0.0/12"
    error_message = "ap-southeast-1 should be 10.48.0.0/12, got ${output.regional_pool_assignments["ap-southeast-1"]}"
  }

  # Capacity should be 6 (4 regions + 2)
  assert {
    condition     = output.required_capacity == 6
    error_message = "Required capacity should be 6, got ${output.required_capacity}"
  }
}

#------------------------------------------------------------------------------
# Test: Legacy allocations are excluded
#------------------------------------------------------------------------------
run "legacy_allocations_excluded" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1", "us-west-2"]
    legacy_allocations = [
      {
        name        = "datacenter-east"
        cidr        = "10.0.0.0/12"
        description = "Legacy datacenter"
      }
    ]
  }

  # Available should be 15 (16 - 1 legacy)
  assert {
    condition     = output.total_available == 15
    error_message = "Total available should be 15 after 1 legacy allocation, got ${output.total_available}"
  }

  # First region should skip the legacy block and get 10.16.0.0/12
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.16.0.0/12"
    error_message = "us-east-1 should skip legacy 10.0.0.0/12 and get 10.16.0.0/12, got ${output.regional_pool_assignments["us-east-1"]}"
  }

  # Second region should get 10.32.0.0/12
  assert {
    condition     = output.regional_pool_assignments["us-west-2"] == "10.32.0.0/12"
    error_message = "us-west-2 should get 10.32.0.0/12, got ${output.regional_pool_assignments["us-west-2"]}"
  }

  # External pool should still be highest available (10.240.0.0/12)
  assert {
    condition     = output.external_pool_cidr == "10.240.0.0/12"
    error_message = "External pool should still be 10.240.0.0/12, got ${output.external_pool_cidr}"
  }

  # Shared pool should still be second-highest available (10.224.0.0/12)
  assert {
    condition     = output.shared_pool_cidr == "10.224.0.0/12"
    error_message = "Shared pool should still be 10.224.0.0/12, got ${output.shared_pool_cidr}"
  }
}

#------------------------------------------------------------------------------
# Test: Multiple legacy allocations in different positions
#------------------------------------------------------------------------------
run "multiple_legacy_allocations" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-1"
        cidr        = "10.0.0.0/12"
        description = "First legacy block"
      },
      {
        name        = "legacy-2"
        cidr        = "10.32.0.0/12"
        description = "Third legacy block"
      },
      {
        name        = "legacy-3"
        cidr        = "10.240.0.0/12"
        description = "Last legacy block (would have been external)"
      }
    ]
  }

  # Available should be 13 (16 - 3 legacy)
  assert {
    condition     = output.total_available == 13
    error_message = "Total available should be 13 after 3 legacy allocations, got ${output.total_available}"
  }

  # First region should get 10.16.0.0/12 (skipping 10.0.0.0/12)
  assert {
    condition     = output.regional_pool_assignments["us-east-1"] == "10.16.0.0/12"
    error_message = "us-east-1 should get 10.16.0.0/12, got ${output.regional_pool_assignments["us-east-1"]}"
  }

  # External pool should be 10.224.0.0/12 (since 10.240.0.0/12 is legacy)
  assert {
    condition     = output.external_pool_cidr == "10.224.0.0/12"
    error_message = "External pool should be 10.224.0.0/12 (highest available after legacy), got ${output.external_pool_cidr}"
  }

  # Shared pool should be 10.208.0.0/12 (second-highest available)
  assert {
    condition     = output.shared_pool_cidr == "10.208.0.0/12"
    error_message = "Shared pool should be 10.208.0.0/12, got ${output.shared_pool_cidr}"
  }
}

#------------------------------------------------------------------------------
# Test: Legacy allocation at top affects shared/external
#------------------------------------------------------------------------------
run "legacy_at_top_shifts_shared_external" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-top"
        cidr        = "10.240.0.0/12"
        description = "Legacy at top"
      },
      {
        name        = "legacy-second-top"
        cidr        = "10.224.0.0/12"
        description = "Legacy at second-to-top"
      }
    ]
  }

  # Available should be 14 (16 - 2 legacy)
  assert {
    condition     = output.total_available == 14
    error_message = "Total available should be 14, got ${output.total_available}"
  }

  # External should shift down to 10.208.0.0/12
  assert {
    condition     = output.external_pool_cidr == "10.208.0.0/12"
    error_message = "External pool should shift to 10.208.0.0/12, got ${output.external_pool_cidr}"
  }

  # Shared should shift down to 10.192.0.0/12
  assert {
    condition     = output.shared_pool_cidr == "10.192.0.0/12"
    error_message = "Shared pool should shift to 10.192.0.0/12, got ${output.shared_pool_cidr}"
  }
}

#------------------------------------------------------------------------------
# Test: Maximum regions without legacy (14 regions possible)
#------------------------------------------------------------------------------
run "maximum_regions_capacity" {
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
  }

  # Required capacity should be 16 (14 regions + 2)
  assert {
    condition     = output.required_capacity == 16
    error_message = "Required capacity should be 16, got ${output.required_capacity}"
  }

  # Should still have sufficient capacity (exactly 16)
  assert {
    condition     = output.has_sufficient_capacity == true
    error_message = "Should have sufficient capacity for 14 regions + shared + external"
  }

  # All 14 regions should be assigned
  assert {
    condition     = length(output.regional_pool_assignments) == 14
    error_message = "Should have 14 regional assignments, got ${length(output.regional_pool_assignments)}"
  }

  # Last region should get 10.208.0.0/12 (index 13)
  assert {
    condition     = output.regional_pool_assignments["ca-central-1"] == "10.208.0.0/12"
    error_message = "Last region should get 10.208.0.0/12, got ${output.regional_pool_assignments["ca-central-1"]}"
  }
}

#------------------------------------------------------------------------------
# Test: Capacity exceeded detection
#------------------------------------------------------------------------------
run "capacity_exceeded_detection" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = [
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2",
      "sa-east-1", "ca-central-1", "af-south-1"
    ]
  }

  # Required capacity should be 17 (15 regions + 2)
  assert {
    condition     = output.required_capacity == 17
    error_message = "Required capacity should be 17, got ${output.required_capacity}"
  }

  # Should NOT have sufficient capacity
  assert {
    condition     = output.has_sufficient_capacity == false
    error_message = "Should NOT have sufficient capacity for 15 regions"
  }
}

#------------------------------------------------------------------------------
# Test: Legacy reduces available capacity
#------------------------------------------------------------------------------
run "legacy_reduces_capacity" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = [
      "us-east-1", "us-east-2", "us-west-1", "us-west-2",
      "eu-west-1", "eu-west-2", "eu-west-3", "eu-central-1",
      "ap-southeast-1", "ap-southeast-2", "ap-northeast-1", "ap-northeast-2"
    ]
    legacy_allocations = [
      {
        name        = "legacy-1"
        cidr        = "10.192.0.0/12"
        description = "Legacy 1"
      },
      {
        name        = "legacy-2"
        cidr        = "10.208.0.0/12"
        description = "Legacy 2"
      },
      {
        name        = "legacy-3"
        cidr        = "10.224.0.0/12"
        description = "Legacy 3"
      }
    ]
  }

  # Required capacity should be 14 (12 regions + 2)
  assert {
    condition     = output.required_capacity == 14
    error_message = "Required capacity should be 14, got ${output.required_capacity}"
  }

  # Available should be 13 (16 - 3 legacy)
  assert {
    condition     = output.total_available == 13
    error_message = "Total available should be 13, got ${output.total_available}"
  }

  # Should NOT have sufficient capacity (14 required > 13 available)
  assert {
    condition     = output.has_sufficient_capacity == false
    error_message = "Should NOT have sufficient capacity with legacy reducing availability"
  }
}

#------------------------------------------------------------------------------
# Test: CIDR ordering is consistent
#------------------------------------------------------------------------------
run "cidr_ordering_consistent" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    target_regions = ["us-east-1"]
  }

  # Verify the CIDR math produces expected /12 boundaries
  # Each /12 should increment by 16 in the second octet
  assert {
    condition     = output.all_slash12_cidrs[2] == "10.32.0.0/12"
    error_message = "Index 2 should be 10.32.0.0/12, got ${output.all_slash12_cidrs[2]}"
  }

  assert {
    condition     = output.all_slash12_cidrs[5] == "10.80.0.0/12"
    error_message = "Index 5 should be 10.80.0.0/12, got ${output.all_slash12_cidrs[5]}"
  }

  assert {
    condition     = output.all_slash12_cidrs[10] == "10.160.0.0/12"
    error_message = "Index 10 should be 10.160.0.0/12, got ${output.all_slash12_cidrs[10]}"
  }
}
