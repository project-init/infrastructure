# Module: iam-role

## Overview

This module creates IAM roles with automatic permission boundary attachment for the **projectvnext ecosystem**.

Every AWS account in the projectvnext organization has a permission boundary that prevents privilege escalation (e.g., modifying VPC configurations, leaving the AWS organization). To enforce this protection consistently, all IAM roles must have the permission boundary attached.

This module removes friction by automatically looking up and attaching the account's permission boundary to every role it creates.

> **Note:** This is an opinionated module designed specifically for use within the projectvnext ecosystem. It assumes a `default-permission-boundary` policy exists in the target account and enforces its attachment to prevent privilege escalation.

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_iam_role` | The IAM role |
| `aws_iam_role_policy` | Inline policies attached to the role (one per policy) |
| `aws_iam_role_policy_attachment` | Managed policy attachments (one per ARN) |
| `aws_iam_instance_profile` | Instance profile for EC2 (only when `is_instance_role = true`) |

## Data Sources

| Data Source | Description |
|-------------|-------------|
| `aws_iam_policy` | Looks up the permission boundary policy by name |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | - | Yes | Name of the IAM role |
| `description` | `string` | - | Yes | Human-readable description of the role's purpose |
| `assume_role_policy` | `string` | `null` | No | JSON trust policy document. Required if `is_instance_role = false` |
| `is_instance_role` | `bool` | `false` | No | When `true`, creates an instance profile and defaults trust policy to EC2 service |
| `inline_policies` | `list(object({ name = string, policy = string }))` | `[]` | No | List of inline policies to attach to the role |
| `managed_policy_arns` | `list(string)` | `[]` | No | List of managed policy ARNs to attach to the role |
| `permission_boundary_name` | `string` | `"default-permission-boundary"` | No | Name of the permission boundary policy to look up and attach |
| `max_session_duration` | `number` | `3600` | No | Maximum session duration in seconds (3600-43200) |
| `path` | `string` | `"/"` | No | IAM path for the role |
| `force_detach_policies` | `bool` | `true` | No | Whether to force detach policies before destroying the role |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply to the role |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | The ARN of the IAM role |
| `role_name` | The name of the IAM role |
| `role_id` | The unique ID of the IAM role |
| `instance_profile_arn` | The ARN of the instance profile (null if `is_instance_role = false`) |
| `instance_profile_name` | The name of the instance profile (null if `is_instance_role = false`) |

## Dependencies

- **Provider:** AWS provider configured for the target account
- **Pre-existing resource:** A permission boundary policy must exist in the account (default name: `default-permission-boundary`)

## Naming Convention

The role is named exactly as provided in the `name` variable. No prefixes or suffixes are added.

Instance profiles (when created) use the same name as the role.

## Tagging

The following tags are automatically applied to the role:

| Tag | Value |
|-----|-------|
| `ManagedBy` | `terraform` |

Additional tags provided via the `tags` variable are merged in. User-provided tags take precedence in case of conflicts.

## Usage Examples

### Basic role with managed policies

```hcl
module "app_role" {
  source = "./modules/iam-role"

  name        = "my-application-role"
  description = "Role for my application to access S3 and DynamoDB"

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
    "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess",
    "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
  ]

  tags = {
    Team    = "Platform"
    Project = "MyApp"
  }
}
```

### EC2 instance role

```hcl
module "ec2_role" {
  source = "./modules/iam-role"

  name             = "web-server-role"
  description      = "Role for web server EC2 instances"
  is_instance_role = true

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
}

# Use the instance profile in an EC2 instance or launch template
resource "aws_instance" "web" {
  # ...
  iam_instance_profile = module.ec2_role.instance_profile_name
}
```

### Role with inline policies

```hcl
module "custom_role" {
  source = "./modules/iam-role"

  name        = "custom-service-role"
  description = "Role with custom inline permissions"

  assume_role_policy = data.aws_iam_policy_document.trust.json

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
```

### Instance role with custom trust policy (power user override)

```hcl
module "ec2_role_custom_trust" {
  source = "./modules/iam-role"

  name             = "special-instance-role"
  description      = "Instance role with custom trust policy"
  is_instance_role = true

  # Power user override: custom trust policy instead of EC2 default
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
```

### Using a different permission boundary

```hcl
module "restricted_role" {
  source = "./modules/iam-role"

  name        = "restricted-role"
  description = "Role with a more restrictive permission boundary"

  permission_boundary_name = "strict-permission-boundary"

  assume_role_policy = data.aws_iam_policy_document.trust.json
}
```

## Implementation Notes

### Permission Boundary Lookup

The module uses a data source to look up the permission boundary by name:

```hcl
data "aws_iam_policy" "permission_boundary" {
  name = var.permission_boundary_name
}
```

The resulting ARN is attached to the role via the `permissions_boundary` argument.

### Trust Policy Logic

```hcl
# Pseudocode for trust policy resolution
locals {
  ec2_trust_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })

  # Use provided policy if set, otherwise default to EC2 for instance roles
  effective_assume_role_policy = coalesce(
    var.assume_role_policy,
    var.is_instance_role ? local.ec2_trust_policy : null
  )
}
```

### Validation

The module should error if `assume_role_policy` is null AND `is_instance_role` is false:

```hcl
variable "assume_role_policy" {
  type    = string
  default = null

  validation {
    condition     = var.assume_role_policy != null || var.is_instance_role
    error_message = "assume_role_policy is required when is_instance_role is false"
  }
}
```

Note: This validation requires a reference to `var.is_instance_role`, which may need to be implemented using a `locals` block with a `null_resource` or `terraform_data` resource with a precondition, or by using a validation in a `locals` block depending on Terraform version capabilities.

### Inline Policy Mapping

Convert the list to a map for `for_each`:

```hcl
locals {
  inline_policies_map = { for p in var.inline_policies : p.name => p.policy }
}

resource "aws_iam_role_policy" "inline" {
  for_each = local.inline_policies_map

  name   = each.key
  role   = aws_iam_role.this.id
  policy = each.value
}
```

### Managed Policy Attachments

```hcl
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
```

### Instance Profile

```hcl
resource "aws_iam_instance_profile" "this" {
  count = var.is_instance_role ? 1 : 0

  name = var.name
  role = aws_iam_role.this.name
  tags = local.merged_tags
}
```

## Out of Scope

This module intentionally does NOT:

- **Create IAM policies** - Users provide policy documents or ARNs; the module only attaches them
- **Manage the permission boundary policy** - The boundary must already exist in the account
- **Create IAM users or groups** - This module is for roles only
- **Create service-linked roles** - These are managed differently by AWS and should use `aws_iam_service_linked_role`
- **Handle cross-account role creation** - The module operates in the account where the provider is configured
