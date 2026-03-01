#------------------------------------------------------------------------------
# IAM Role Module Tests
# Consolidated tests for validation, trust policy logic, and resource structure
#------------------------------------------------------------------------------

mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Statement\":[{\"Action\":\"sts:AssumeRole\",\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"ec2.amazonaws.com\"}}],\"Version\":\"2012-10-17\"}"
    }
  }
}

#------------------------------------------------------------------------------
# Test: Valid configuration - standard role with trust policy
#------------------------------------------------------------------------------
run "valid_standard_role" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name        = "lambda-execution-role"
    description = "Role for Lambda function execution"

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
    })

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
    ]

    tags = {
      Team    = "Platform"
      Project = "MyApp"
    }
  }

  # Validation should pass
  assert {
    condition     = output.validation_passed == true
    error_message = "Validation should pass when assume_role_policy is provided"
  }

  # Trust policy should use the provided one
  assert {
    condition     = output.is_ec2_trust_policy == false
    error_message = "Trust policy should not be EC2 default when custom policy provided"
  }

  assert {
    condition     = strcontains(output.effective_assume_role_policy, "lambda.amazonaws.com")
    error_message = "Trust policy should contain Lambda service"
  }

  # Resource counts
  assert {
    condition     = output.managed_policy_count == 1
    error_message = "Should have 1 managed policy attachment"
  }

  assert {
    condition     = output.inline_policy_count == 0
    error_message = "Should have 0 inline policies"
  }

  # Instance profile should not be created
  assert {
    condition     = output.should_create_instance_profile == false
    error_message = "Should not create instance profile for non-instance role"
  }

  assert {
    condition     = output.mock_instance_profile_arn == null
    error_message = "Instance profile ARN should be null"
  }

  # Tags should include default ManagedBy
  assert {
    condition     = output.has_managed_by_tag == true
    error_message = "Should have ManagedBy = tofu tag"
  }

  assert {
    condition     = output.merged_tags["Team"] == "Platform" && output.merged_tags["Project"] == "MyApp"
    error_message = "Custom tags should be merged"
  }
}

#------------------------------------------------------------------------------
# Test: EC2 Instance Role with default trust policy
#------------------------------------------------------------------------------
run "ec2_instance_role_default_trust" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name             = "web-server-role"
    description      = "Role for web server EC2 instances"
    is_instance_role = true

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]
  }

  # Validation should pass without assume_role_policy
  assert {
    condition     = output.validation_passed == true
    error_message = "Validation should pass for instance role without explicit trust policy"
  }

  # Should use EC2 default trust policy
  assert {
    condition     = output.is_ec2_trust_policy == true
    error_message = "Should use EC2 default trust policy"
  }

  assert {
    condition     = strcontains(output.effective_assume_role_policy, "ec2.amazonaws.com")
    error_message = "Trust policy should contain EC2 service"
  }

  # Instance profile should be created
  assert {
    condition     = output.should_create_instance_profile == true
    error_message = "Should create instance profile for EC2 role"
  }

  assert {
    condition     = output.mock_instance_profile_name == "web-server-role"
    error_message = "Instance profile name should match role name"
  }

  assert {
    condition     = output.mock_instance_profile_arn != null
    error_message = "Instance profile ARN should not be null"
  }
}

#------------------------------------------------------------------------------
# Test: EC2 Instance Role with custom trust policy (power user override)
#------------------------------------------------------------------------------
run "ec2_instance_role_custom_trust" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name             = "special-instance-role"
    description      = "Instance role with custom trust policy"
    is_instance_role = true

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = ["ec2.amazonaws.com", "ssm.amazonaws.com"]
        }
      }]
    })

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    ]
  }

  # Should use provided trust policy, not EC2 default
  assert {
    condition     = output.is_ec2_trust_policy == false
    error_message = "Should use custom trust policy, not EC2 default"
  }

  assert {
    condition     = strcontains(output.effective_assume_role_policy, "ssm.amazonaws.com")
    error_message = "Trust policy should contain SSM service"
  }

  # Still creates instance profile
  assert {
    condition     = output.should_create_instance_profile == true
    error_message = "Should still create instance profile with custom trust policy"
  }
}

#------------------------------------------------------------------------------
# Test: Validation failure - missing assume_role_policy for non-instance role
#------------------------------------------------------------------------------
run "validation_fails_without_trust_policy" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name        = "invalid-role"
    description = "Role without trust policy"
    # is_instance_role defaults to false
    # assume_role_policy defaults to null
  }

  assert {
    condition     = output.validation_passed == false
    error_message = "Validation should fail when assume_role_policy is null and is_instance_role is false"
  }

  assert {
    condition     = output.has_assume_role_policy == false
    error_message = "Should report no assume_role_policy provided"
  }

  assert {
    condition     = output.is_instance_role == false
    error_message = "is_instance_role should be false"
  }
}

#------------------------------------------------------------------------------
# Test: Role with inline policies
#------------------------------------------------------------------------------
run "role_with_inline_policies" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name        = "custom-service-role"
    description = "Role with custom inline permissions"

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }]
    })

    inline_policies = [
      {
        name = "s3-access"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["s3:GetObject", "s3:ListBucket"]
            Resource = ["arn:aws:s3:::my-bucket", "arn:aws:s3:::my-bucket/*"]
          }]
        })
      },
      {
        name = "sqs-access"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["sqs:SendMessage", "sqs:ReceiveMessage"]
            Resource = "arn:aws:sqs:us-east-1:123456789012:my-queue"
          }]
        })
      }
    ]
  }

  assert {
    condition     = output.inline_policy_count == 2
    error_message = "Should have 2 inline policies"
  }

  assert {
    condition     = contains(output.inline_policy_names, "s3-access")
    error_message = "Should have s3-access inline policy"
  }

  assert {
    condition     = contains(output.inline_policy_names, "sqs-access")
    error_message = "Should have sqs-access inline policy"
  }
}

#------------------------------------------------------------------------------
# Test: Custom permission boundary
#------------------------------------------------------------------------------
run "custom_permission_boundary" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name                     = "restricted-role"
    description              = "Role with a more restrictive permission boundary"
    permission_boundary_name = "strict-permission-boundary"

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }]
    })
  }

  assert {
    condition     = output.is_valid_permission_boundary == true
    error_message = "Custom permission boundary should be valid"
  }

  assert {
    condition     = strcontains(output.mock_permission_boundary_arn, "strict-permission-boundary")
    error_message = "Permission boundary ARN should contain the custom name"
  }
}

#------------------------------------------------------------------------------
# Test: Multiple managed policies
#------------------------------------------------------------------------------
run "multiple_managed_policies" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name        = "multi-policy-role"
    description = "Role with multiple managed policies"

    assume_role_policy = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }]
    })

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
      "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess",
      "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
    ]
  }

  assert {
    condition     = output.managed_policy_count == 3
    error_message = "Should have 3 managed policy attachments"
  }
}

#------------------------------------------------------------------------------
# Test: Complex configuration - instance role with inline and managed policies
#------------------------------------------------------------------------------
run "complex_instance_role" {
  command = plan

  module {
    source = "./tests/setup"
  }

  variables {
    name             = "complex-ec2-role"
    description      = "Complex EC2 role with multiple policies"
    is_instance_role = true

    managed_policy_arns = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    ]

    inline_policies = [
      {
        name = "app-specific"
        policy = jsonencode({
          Version = "2012-10-17"
          Statement = [{
            Effect   = "Allow"
            Action   = ["s3:GetObject"]
            Resource = "arn:aws:s3:::config-bucket/*"
          }]
        })
      }
    ]

    tags = {
      Environment = "production"
      CostCenter  = "engineering"
    }
  }

  # All resources should be created
  assert {
    condition     = output.should_create_instance_profile == true
    error_message = "Should create instance profile"
  }

  assert {
    condition     = output.managed_policy_count == 2
    error_message = "Should have 2 managed policies"
  }

  assert {
    condition     = output.inline_policy_count == 1
    error_message = "Should have 1 inline policy"
  }

  # Trust policy should be EC2 default
  assert {
    condition     = output.is_ec2_trust_policy == true
    error_message = "Should use EC2 default trust policy"
  }

  # Tags should be merged
  assert {
    condition     = output.merged_tags["Environment"] == "production"
    error_message = "Environment tag should be present"
  }

  assert {
    condition     = output.merged_tags["CostCenter"] == "engineering"
    error_message = "CostCenter tag should be present"
  }

  assert {
    condition     = output.merged_tags["ManagedBy"] == "tofu"
    error_message = "ManagedBy tag should be present"
  }
}
