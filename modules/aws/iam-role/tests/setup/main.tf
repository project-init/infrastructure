#------------------------------------------------------------------------------
# IAM Role Test Setup Module
# Exposes the IAM role module logic for unit testing without AWS resources
# Uses mock data to simulate IAM behavior
#------------------------------------------------------------------------------

variable "name" {
  description = "Name of the IAM role"
  type        = string
  default     = "test-role"
}

variable "description" {
  description = "Human-readable description of the role's purpose"
  type        = string
  default     = "Test role"
}

variable "assume_role_policy" {
  description = "JSON trust policy document. Required if is_instance_role = false"
  type        = string
  default     = null
}

variable "is_instance_role" {
  description = "When true, creates an instance profile and defaults trust policy to EC2"
  type        = bool
  default     = false
}

variable "inline_policies" {
  description = "List of inline policies to attach to the role"
  type = list(object({
    name   = string
    policy = string
  }))
  default = []
}

variable "managed_policy_arns" {
  description = "List of managed policy ARNs to attach to the role"
  type        = list(string)
  default     = []
}

variable "permission_boundary_name" {
  description = "Name of the permission boundary policy to look up and attach"
  type        = string
  default     = "default-permission-boundary"
}

variable "tags" {
  description = "Additional tags to apply to the role"
  type        = map(string)
  default     = {}
}

data "aws_iam_policy_document" "ec2_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

locals {
  # EC2 default trust policy
  ec2_trust_policy = data.aws_iam_policy_document.ec2_trust.json

  # Validation: assume_role_policy required when is_instance_role is false
  has_assume_role_policy = var.assume_role_policy != null
  validation_passed      = var.is_instance_role || local.has_assume_role_policy

  # Effective trust policy resolution
  effective_assume_role_policy = var.assume_role_policy != null ? var.assume_role_policy : (
    var.is_instance_role ? local.ec2_trust_policy : null
  )

  # Permission boundary validation (simulated)
  valid_permission_boundary_names = [
    "default-permission-boundary",
    "strict-permission-boundary",
    "custom-boundary"
  ]
  is_valid_permission_boundary = contains(local.valid_permission_boundary_names, var.permission_boundary_name)

  # Mock permission boundary ARN
  mock_permission_boundary_arn = "arn:aws:iam::123456789012:policy/${var.permission_boundary_name}"

  # Merge default tags with user tags
  merged_tags = merge(
    {
      ManagedBy = "tofu"
    },
    var.tags
  )

  # Convert inline policies list to map
  inline_policies_map = { for p in var.inline_policies : p.name => p.policy }

  # Resource counts
  inline_policy_count            = length(var.inline_policies)
  managed_policy_count           = length(var.managed_policy_arns)
  should_create_instance_profile = var.is_instance_role

  # Mock outputs
  mock_role_arn              = "arn:aws:iam::123456789012:role/${var.name}"
  mock_role_id               = "AROA${substr(md5(var.name), 0, 17)}"
  mock_instance_profile_arn  = var.is_instance_role ? "arn:aws:iam::123456789012:instance-profile/${var.name}" : null
  mock_instance_profile_name = var.is_instance_role ? var.name : null
}

#------------------------------------------------------------------------------
# Validation Outputs
#------------------------------------------------------------------------------
output "validation_passed" {
  description = "Whether validation passed (assume_role_policy provided or is_instance_role = true)"
  value       = local.validation_passed
}

output "has_assume_role_policy" {
  description = "Whether assume_role_policy was provided"
  value       = local.has_assume_role_policy
}

output "is_instance_role" {
  description = "Value of is_instance_role variable"
  value       = var.is_instance_role
}

#------------------------------------------------------------------------------
# Trust Policy Outputs
#------------------------------------------------------------------------------
output "effective_assume_role_policy" {
  description = "The effective trust policy that would be used"
  value       = local.effective_assume_role_policy
}

output "is_ec2_trust_policy" {
  description = "Whether the effective trust policy is the EC2 default"
  value       = local.effective_assume_role_policy == local.ec2_trust_policy
}

#------------------------------------------------------------------------------
# Permission Boundary Outputs
#------------------------------------------------------------------------------
output "is_valid_permission_boundary" {
  description = "Whether the permission boundary name is valid"
  value       = local.is_valid_permission_boundary
}

output "mock_permission_boundary_arn" {
  description = "Mock ARN for the permission boundary"
  value       = local.mock_permission_boundary_arn
}

#------------------------------------------------------------------------------
# Resource Count Outputs
#------------------------------------------------------------------------------
output "inline_policy_count" {
  description = "Number of inline policies to be created"
  value       = local.inline_policy_count
}

output "managed_policy_count" {
  description = "Number of managed policy attachments"
  value       = local.managed_policy_count
}

output "should_create_instance_profile" {
  description = "Whether an instance profile should be created"
  value       = local.should_create_instance_profile
}

#------------------------------------------------------------------------------
# Tag Outputs
#------------------------------------------------------------------------------
output "merged_tags" {
  description = "Merged tags including default ManagedBy tag"
  value       = local.merged_tags
}

output "has_managed_by_tag" {
  description = "Whether the merged tags include ManagedBy = tofu"
  value       = lookup(local.merged_tags, "ManagedBy", "") == "tofu"
}

#------------------------------------------------------------------------------
# Mock Resource Outputs
#------------------------------------------------------------------------------
output "mock_role_arn" {
  description = "Mock ARN for the IAM role"
  value       = local.mock_role_arn
}

output "mock_role_name" {
  description = "Mock name for the IAM role"
  value       = var.name
}

output "mock_role_id" {
  description = "Mock unique ID for the IAM role"
  value       = local.mock_role_id
}

output "mock_instance_profile_arn" {
  description = "Mock ARN for the instance profile (null if not an instance role)"
  value       = local.mock_instance_profile_arn
}

output "mock_instance_profile_name" {
  description = "Mock name for the instance profile (null if not an instance role)"
  value       = local.mock_instance_profile_name
}

#------------------------------------------------------------------------------
# Inline Policies Map
#------------------------------------------------------------------------------
output "inline_policies_map" {
  description = "Map of inline policy names to policy documents"
  value       = local.inline_policies_map
}

output "inline_policy_names" {
  description = "List of inline policy names"
  value       = keys(local.inline_policies_map)
}
