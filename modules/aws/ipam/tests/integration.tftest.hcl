#------------------------------------------------------------------------------
# Integration Tests
# Tests the full module with mocked AWS provider
#------------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_region" {
    defaults = {
      id          = "us-east-1"
      name        = "us-east-1"
      description = "US East (N. Virginia)"
      endpoint    = "ec2.us-east-1.amazonaws.com"
    }
  }
}

#------------------------------------------------------------------------------
# Test: Basic module instantiation
#------------------------------------------------------------------------------
run "basic_module_plan" {
  command = plan

  variables {
    target_regions = ["us-east-1", "us-west-2"]
    tags = {
      Environment = "test"
      Project     = "ipam-testing"
    }
  }

  # Verify IPAM resource is planned
  assert {
    condition     = aws_vpc_ipam.this.description == "Platform IPAM for centralized IP address management"
    error_message = "IPAM description should be set correctly"
  }

  # Verify global pool is planned
  assert {
    condition     = aws_vpc_ipam_pool.global.address_family == "ipv4"
    error_message = "Global pool should be IPv4"
  }

  # Verify global pool CIDR
  assert {
    condition     = aws_vpc_ipam_pool_cidr.global.cidr == "10.0.0.0/8"
    error_message = "Global pool CIDR should be 10.0.0.0/8"
  }
}

#------------------------------------------------------------------------------
# Test: Regional pools created for each target region
#------------------------------------------------------------------------------
run "regional_pools_created" {
  command = plan

  variables {
    target_regions = ["us-east-1", "us-west-2", "eu-west-1"]
  }

  # Verify regional pools are created for each region
  assert {
    condition     = aws_vpc_ipam_pool.regional["us-east-1"].locale == "us-east-1"
    error_message = "us-east-1 regional pool should have correct locale"
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["us-west-2"].locale == "us-west-2"
    error_message = "us-west-2 regional pool should have correct locale"
  }

  assert {
    condition     = aws_vpc_ipam_pool.regional["eu-west-1"].locale == "eu-west-1"
    error_message = "eu-west-1 regional pool should have correct locale"
  }

  # Verify regional pool CIDRs follow bottom-up allocation
  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-east-1"].cidr == "10.0.0.0/12"
    error_message = "us-east-1 should get 10.0.0.0/12"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-west-2"].cidr == "10.16.0.0/12"
    error_message = "us-west-2 should get 10.16.0.0/12"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["eu-west-1"].cidr == "10.32.0.0/12"
    error_message = "eu-west-1 should get 10.32.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: Shared and external pools created with top-down allocation
#------------------------------------------------------------------------------
run "shared_external_pools_created" {
  command = plan

  variables {
    target_regions = ["us-east-1"]
  }

  # Verify shared pool exists and has correct description
  assert {
    condition     = aws_vpc_ipam_pool.shared.description == "Shared pool for Shared VPCs"
    error_message = "Shared pool should have correct description"
  }

  # Verify external pool exists and has correct description
  assert {
    condition     = aws_vpc_ipam_pool.external.description == "External pool for integrations"
    error_message = "External pool should have correct description"
  }

  # Verify shared pool gets second-highest CIDR
  assert {
    condition     = aws_vpc_ipam_pool_cidr.shared.cidr == "10.224.0.0/12"
    error_message = "Shared pool should get 10.224.0.0/12"
  }

  # Verify external pool gets highest CIDR
  assert {
    condition     = aws_vpc_ipam_pool_cidr.external.cidr == "10.240.0.0/12"
    error_message = "External pool should get 10.240.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: Legacy allocations create reservations
#------------------------------------------------------------------------------
run "legacy_allocations_reserved" {
  command = plan

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "datacenter-east"
        cidr        = "10.48.0.0/12"
        description = "On-premises datacenter"
      },
      {
        name        = "partner-network"
        cidr        = "10.64.0.0/12"
        description = "Partner integration network"
      }
    ]
  }

  # Verify legacy allocations are created
  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.legacy["datacenter-east"].cidr == "10.48.0.0/12"
    error_message = "datacenter-east legacy allocation should reserve 10.48.0.0/12"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.legacy["partner-network"].cidr == "10.64.0.0/12"
    error_message = "partner-network legacy allocation should reserve 10.64.0.0/12"
  }

  # Verify descriptions are set
  assert {
    condition     = can(regex("datacenter-east", aws_vpc_ipam_pool_cidr_allocation.legacy["datacenter-east"].description))
    error_message = "Legacy allocation description should include the name"
  }
}

#------------------------------------------------------------------------------
# Test: Tags are applied correctly
#------------------------------------------------------------------------------
run "tags_applied_correctly" {
  command = plan

  variables {
    target_regions = ["us-east-1"]
    tags = {
      Environment = "production"
      Team        = "platform"
      CostCenter  = "12345"
    }
  }

  # Verify IPAM has correct tags
  assert {
    condition     = aws_vpc_ipam.this.tags["Environment"] == "production"
    error_message = "IPAM should have Environment tag"
  }

  assert {
    condition     = aws_vpc_ipam.this.tags["Team"] == "platform"
    error_message = "IPAM should have Team tag"
  }

  assert {
    condition     = aws_vpc_ipam.this.tags["Module"] == "ipam"
    error_message = "IPAM should have Module tag (auto-applied)"
  }

  # Verify global pool has Tier tag
  assert {
    condition     = aws_vpc_ipam_pool.global.tags["Tier"] == "global"
    error_message = "Global pool should have Tier=global tag"
  }

  # Verify shared pool has Tier tag
  assert {
    condition     = aws_vpc_ipam_pool.shared.tags["Tier"] == "shared"
    error_message = "Shared pool should have Tier=shared tag"
  }

  # Verify external pool has Tier tag
  assert {
    condition     = aws_vpc_ipam_pool.external.tags["Tier"] == "external"
    error_message = "External pool should have Tier=external tag"
  }
}

#------------------------------------------------------------------------------
# Test: Regional pool has correct default netmask
#------------------------------------------------------------------------------
run "regional_pool_netmask_settings" {
  command = plan

  variables {
    target_regions = ["us-east-1"]
  }

  # Regional pools should default to /16 for VPCs
  assert {
    condition     = aws_vpc_ipam_pool.regional["us-east-1"].allocation_default_netmask_length == 16
    error_message = "Regional pool should have default netmask of /16"
  }

  # Shared pool should default to /15
  assert {
    condition     = aws_vpc_ipam_pool.shared.allocation_default_netmask_length == 15
    error_message = "Shared pool should have default netmask of /15"
  }

  # External pool should default to /16
  assert {
    condition     = aws_vpc_ipam_pool.external.allocation_default_netmask_length == 16
    error_message = "External pool should have default netmask of /16"
  }
}

#------------------------------------------------------------------------------
# Test: Outputs are correctly structured
#------------------------------------------------------------------------------
run "outputs_structured_correctly" {
  command = plan

  variables {
    target_regions = ["us-east-1", "us-west-2"]
  }

  # Verify regional_pools output structure
  assert {
    condition     = output.regional_pools["us-east-1"].cidr == "10.0.0.0/12"
    error_message = "regional_pools output should include CIDR for us-east-1"
  }

  assert {
    condition     = output.regional_pools["us-west-2"].cidr == "10.16.0.0/12"
    error_message = "regional_pools output should include CIDR for us-west-2"
  }

  # Verify regional_pool_ids output
  assert {
    condition     = length(output.regional_pool_ids) == 2
    error_message = "regional_pool_ids should have 2 entries"
  }

  # Verify shared pool CIDR output
  assert {
    condition     = output.shared_pool_cidr == "10.224.0.0/12"
    error_message = "shared_pool_cidr output should be 10.224.0.0/12"
  }

  # Verify external pool CIDR output
  assert {
    condition     = output.external_pool_cidr == "10.240.0.0/12"
    error_message = "external_pool_cidr output should be 10.240.0.0/12"
  }

  # Verify allocation_summary output
  assert {
    condition     = output.allocation_summary.global_cidr == "10.0.0.0/8"
    error_message = "allocation_summary should include global_cidr"
  }
}

#------------------------------------------------------------------------------
# Test: Legacy allocations affect regional assignment
#------------------------------------------------------------------------------
run "legacy_affects_regional_assignment" {
  command = plan

  variables {
    target_regions = ["us-east-1", "us-west-2"]
    legacy_allocations = [
      {
        name        = "legacy-first"
        cidr        = "10.0.0.0/12"
        description = "Blocks first CIDR"
      }
    ]
  }

  # us-east-1 should skip the legacy block
  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-east-1"].cidr == "10.16.0.0/12"
    error_message = "us-east-1 should get 10.16.0.0/12, skipping legacy 10.0.0.0/12"
  }

  # us-west-2 should get next available
  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-west-2"].cidr == "10.32.0.0/12"
    error_message = "us-west-2 should get 10.32.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: Shared pool override in full module
#------------------------------------------------------------------------------
run "shared_pool_override_integration" {
  command = plan

  variables {
    target_regions            = ["us-east-1", "us-west-2"]
    shared_pool_cidr_override = "10.128.0.0/12"
  }

  # Shared pool should use override
  assert {
    condition     = aws_vpc_ipam_pool_cidr.shared.cidr == "10.128.0.0/12"
    error_message = "Shared pool should use override 10.128.0.0/12"
  }

  # External should still be top-down (highest available)
  assert {
    condition     = aws_vpc_ipam_pool_cidr.external.cidr == "10.240.0.0/12"
    error_message = "External pool should be 10.240.0.0/12"
  }

  # Regional should not be affected
  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-east-1"].cidr == "10.0.0.0/12"
    error_message = "us-east-1 should still get 10.0.0.0/12"
  }

  # Output should reflect override
  assert {
    condition     = output.shared_pool_cidr == "10.128.0.0/12"
    error_message = "Output shared_pool_cidr should be 10.128.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: External pool override in full module
#------------------------------------------------------------------------------
run "external_pool_override_integration" {
  command = plan

  variables {
    target_regions              = ["us-east-1"]
    external_pool_cidr_override = "10.64.0.0/12"
  }

  # External pool should use override
  assert {
    condition     = aws_vpc_ipam_pool_cidr.external.cidr == "10.64.0.0/12"
    error_message = "External pool should use override 10.64.0.0/12"
  }

  # Shared should get highest available (since external is overridden)
  assert {
    condition     = aws_vpc_ipam_pool_cidr.shared.cidr == "10.240.0.0/12"
    error_message = "Shared pool should be 10.240.0.0/12 (highest available)"
  }

  # Output should reflect override
  assert {
    condition     = output.external_pool_cidr == "10.64.0.0/12"
    error_message = "Output external_pool_cidr should be 10.64.0.0/12"
  }
}

#------------------------------------------------------------------------------
# Test: Both overrides in full module
#------------------------------------------------------------------------------
run "both_overrides_integration" {
  command = plan

  variables {
    target_regions              = ["us-east-1", "us-west-2", "eu-west-1"]
    shared_pool_cidr_override   = "10.96.0.0/12"
    external_pool_cidr_override = "10.112.0.0/12"
  }

  # Both pools should use overrides
  assert {
    condition     = aws_vpc_ipam_pool_cidr.shared.cidr == "10.96.0.0/12"
    error_message = "Shared pool should use override"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.external.cidr == "10.112.0.0/12"
    error_message = "External pool should use override"
  }

  # Regional assignments should be unaffected (bottom-up from lowest)
  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-east-1"].cidr == "10.0.0.0/12"
    error_message = "us-east-1 should get 10.0.0.0/12"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["us-west-2"].cidr == "10.16.0.0/12"
    error_message = "us-west-2 should get 10.16.0.0/12"
  }

  assert {
    condition     = aws_vpc_ipam_pool_cidr.regional["eu-west-1"].cidr == "10.32.0.0/12"
    error_message = "eu-west-1 should get 10.32.0.0/12"
  }

  # Outputs should reflect overrides
  assert {
    condition     = output.shared_pool_cidr == "10.96.0.0/12"
    error_message = "Output should reflect shared override"
  }

  assert {
    condition     = output.external_pool_cidr == "10.112.0.0/12"
    error_message = "Output should reflect external override"
  }
}

#------------------------------------------------------------------------------
# Test: Override with legacy allocations in full module
#------------------------------------------------------------------------------
run "override_with_legacy_integration" {
  command = plan

  variables {
    target_regions = ["us-east-1"]
    legacy_allocations = [
      {
        name        = "legacy-top"
        cidr        = "10.240.0.0/12"
        description = "Legacy at top"
      }
    ]
    shared_pool_cidr_override = "10.128.0.0/12"
  }

  # Shared should use override
  assert {
    condition     = aws_vpc_ipam_pool_cidr.shared.cidr == "10.128.0.0/12"
    error_message = "Shared pool should use override"
  }

  # External should be highest available after legacy exclusion (10.224.0.0/12)
  assert {
    condition     = aws_vpc_ipam_pool_cidr.external.cidr == "10.224.0.0/12"
    error_message = "External pool should be 10.224.0.0/12 (highest after legacy)"
  }

  # Legacy allocation should still be created
  assert {
    condition     = aws_vpc_ipam_pool_cidr_allocation.legacy["legacy-top"].cidr == "10.240.0.0/12"
    error_message = "Legacy allocation should be created"
  }
}
