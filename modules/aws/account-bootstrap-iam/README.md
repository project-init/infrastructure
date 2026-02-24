# Account Bootstrap IAM Module

This module configures the IAM foundation in a sibling account to allow the Platform Account to manage it. It creates the `platform-execution` role that enforces a "Reader" vs "Deployer" permission model based on session tags.

## Overview

The module is responsible for:
- Creating the `platform-execution` IAM role in the target account
- Establishing trust with `platform-reader-admin` and `platform-deployer-admin` roles from the Platform Account
- Granting ReadOnly access to all principals
- Granting Administrator access conditionally when the `Role=Deployer` session tag is present

## Prerequisites

- Must be executed with credentials that can assume into the **Target (Sibling) Account**
- The `platform-reader-admin` and `platform-deployer-admin` roles must exist in the Platform Account (created by the `platform-bootstrap-iam` module)

## Usage

```hcl
module "account_bootstrap_iam" {
  source = "./modules/account-bootstrap-iam"

  platform_account_id = "123456789012"
  organization        = "acme"
  namespace           = "analytics"
  environment         = "production"

  tags = {
    Team    = "Platform"
    Project = "Infrastructure"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `platform_account_id` | `string` | - | Yes | The AWS Account ID of the Platform Account. |
| `organization` | `string` | - | Yes | The organization name (e.g., `acme`). Used for tagging. |
| `namespace` | `string` | - | Yes | The namespace for the account (e.g., `core`, `analytics`). Used for tagging. |
| `environment` | `string` | - | Yes | The environment. Must be one of: `staging`, `production`, `global`. |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply to resources. |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the `platform-execution` role. |
| `role_name` | Name of the `platform-execution` role. |

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_iam_role.platform_execution` | The `platform-execution` IAM role |
| `aws_iam_role_policy_attachment.readonly` | Attachment of AWS managed `ReadOnlyAccess` policy |
| `aws_iam_role_policy.admin_access` | Inline policy for conditional administrator access |

## How It Works

### Trust Policy

The `platform-execution` role has separate trust statements for Reader and Deployer roles to prevent privilege escalation:

**Reader (`platform-reader-admin`):**
- Can only perform `sts:AssumeRole`
- Cannot tag sessions, preventing escalation to Deployer privileges

**Deployer (`platform-deployer-admin`):**
- Can perform `sts:AssumeRole` and `sts:TagSession`
- Session tags are constrained:
  - `aws:RequestTag/Role` must equal `Deployer`
  - Only the `Role` tag key is allowed (`aws:TagKeys`)

### Permissions Model

1. **ReadOnly Access**: All principals (both Reader and Deployer) receive the AWS managed `ReadOnlyAccess` policy unconditionally.

2. **Administrator Access**: Full `*:*` permissions are granted only when the session tag `aws:PrincipalTag/Role` equals `Deployer`. This condition is evaluated at runtime, so Readers cannot escalate privileges.

This creates a permission model where:
- **Readers** can view all resources but cannot modify anything
- **Deployers** can view and modify all resources

## Tagging

The following tags are automatically applied to the role:
- `PlatformManaged = true` - Identifies resources managed by the platform (for SCP/Permission Boundary protection)
- `Organization` - from `var.organization`
- `Namespace` - from `var.namespace`
- `Environment` - from `var.environment`

Additional tags can be merged via the `tags` variable. **Note:** System tags cannot be overridden by `var.tags` to ensure security properties are maintained.

## Security Considerations

- **Privilege Escalation Prevention**: The trust policy explicitly prevents Readers from using `sts:TagSession`, so they cannot pass `Role=Deployer` to gain admin access
- **Session Tag Constraints**: Deployers can only pass the `Role` tag with value `Deployer`, preventing arbitrary tag injection
- **System Tag Protection**: The `PlatformManaged=true` tag cannot be overridden via `var.tags`, ensuring SCPs and Permission Boundaries can reliably identify platform resources
- **Conditional Admin Access**: Even if a Reader's credentials are compromised, they cannot modify resources

## Related Modules

- **platform-bootstrap-iam** - Creates the jump host roles (`platform-reader-admin`, `platform-deployer-admin`) in the Platform Account
- **account** - Creates new AWS accounts within AWS Organizations
- **account-baseline** - Configures account-level settings (alias, password policy, etc.)
