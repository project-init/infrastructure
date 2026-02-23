# IAM Role Module

Creates IAM roles with automatic permission boundary enforcement for the projectvnext ecosystem.

## Why This Module Exists

Every AWS account in the projectvnext organization has a permission boundary that prevents privilege escalation (modifying VPC configurations, leaving the organization, etc.). For security, **all IAM roles must have this boundary attached**.

This module removes friction by:
- **Automatically looking up** your account's permission boundary
- **Enforcing attachment** on every role it creates
- Providing a **simple interface** for common role patterns (EC2 instances, Lambda functions, etc.)

Without this module, you'd need to manually look up and attach the permission boundary every time you create a role—easy to forget, with security implications.

## What This Module Does

1. **Creates an IAM role** with your specified trust policy
2. **Attaches the permission boundary** automatically (looks it up by name)
3. **Attaches managed policies** (optional)
4. **Creates inline policies** (optional)
5. **Creates an instance profile** for EC2 roles (optional)

## Usage

### Basic Role with Managed Policies

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

### EC2 Instance Role

For EC2 instances, set `is_instance_role = true` to automatically create an instance profile:

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

# Use the instance profile
resource "aws_instance" "web" {
  # ...
  iam_instance_profile = module.ec2_role.instance_profile_name
}
```

The module defaults the trust policy to EC2 when `is_instance_role = true`. You can still provide a custom trust policy if needed.

### Role with Inline Policies

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
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform/opentofu | >= 1.0.0 |
| aws | ~> 6.0 |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | - | Yes | Name of the IAM role |
| `description` | `string` | - | Yes | Human-readable description of the role's purpose |
| `assume_role_policy` | `string` | `null` | No | JSON trust policy document. Required if `is_instance_role = false` |
| `is_instance_role` | `bool` | `false` | No | When `true`, creates an instance profile and defaults trust policy to EC2 |
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

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_iam_role` | The IAM role with permission boundary attached |
| `aws_iam_role_policy` | Inline policies attached to the role (one per policy) |
| `aws_iam_role_policy_attachment` | Managed policy attachments (one per ARN) |
| `aws_iam_instance_profile` | Instance profile for EC2 (only when `is_instance_role = true`) |

## Dependencies

- **Pre-existing resource**: A permission boundary policy must exist in the account (default name: `default-permission-boundary`)
- **AWS Provider**: Must be configured for the target account

## Tagging

The following tag is automatically applied to all resources:

| Tag | Value |
|-----|-------|
| `ManagedBy` | `tofu` |

Additional tags provided via the `tags` variable are merged in. User-provided tags take precedence in case of conflicts.

## Validation

The module enforces:

- **`assume_role_policy` is required** when `is_instance_role = false`
- Permission boundary policy must exist in the account
- Role name, description, and policies follow AWS IAM constraints

## What This Module Does NOT Do

- **Create IAM policies** - You provide policy documents or ARNs; the module only attaches them
- **Manage the permission boundary policy** - The boundary must already exist in the account (created by platform team)
- **Create IAM users or groups** - This module is for roles only
- **Create service-linked roles** - Use `aws_iam_service_linked_role` for those
- **Handle cross-account role creation** - Operates in the account where the provider is configured

## Permission Boundary

By default, the module looks up a policy named `default-permission-boundary`. You can specify a different name:

```hcl
module "restricted_role" {
  source = "./modules/iam-role"

  name                     = "restricted-role"
  description              = "Role with a more restrictive permission boundary"
  permission_boundary_name = "strict-permission-boundary"

  assume_role_policy = data.aws_iam_policy_document.trust.json
}
```

Contact your platform team if you need a custom permission boundary for your use case.
