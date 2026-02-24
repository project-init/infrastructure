# Platform Bootstrap IAM Module

This module creates the "Jump Host" IAM roles in the Platform Account that users assume (via `credential_process`) to manage infrastructure across the organization.

## Overview

The module is responsible for:
- Creating `platform-reader-admin` and `platform-deployer-admin` IAM roles
- Enforcing strict session tagging to propagate permissions downstream
- Ensuring the `credential_process` script passes the appropriate `Role` tag during assumption

## Prerequisites

- Must be executed with credentials in the **Platform Account**
- A local `credential_process` script must be configured to perform `AssumeRole` with transitive tags

## Usage

```hcl
module "platform_bootstrap_iam" {
  source = "./modules/platform-bootstrap-iam"

  allowed_principals = [
    "arn:aws:iam::123456789012:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdminAccess_abc123",
    "arn:aws:iam::123456789012:user/admin"
  ]

  tags = {
    Team    = "Platform"
    Project = "Infrastructure"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `allowed_principals` | `list(string)` | - | Yes | List of ARNs (SSO Roles or Users) allowed to assume these roles. |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply. |

## Outputs

| Name | Description |
|------|-------------|
| `reader_role_arn` | ARN of `platform-reader-admin` |
| `deployer_role_arn` | ARN of `platform-deployer-admin` |

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_iam_role.reader` | The `platform-reader-admin` IAM role |
| `aws_iam_role.deployer` | The `platform-deployer-admin` IAM role |
| `aws_iam_role_policy.reader` | Inline policy allowing reader to assume `platform-execution` roles |
| `aws_iam_role_policy.deployer` | Inline policy allowing deployer to assume `platform-execution` roles |

## How It Works

### Trust Policies

Both roles require the caller to pass a session tag during assumption:

- **`platform-reader-admin`**: Requires `aws:RequestTag/Role = Reader`
- **`platform-deployer-admin`**: Requires `aws:RequestTag/Role = Deployer`

This ensures that the `credential_process` script must explicitly declare the permission level being requested.

### Permissions Policies

Each role can assume `platform-execution` roles in any account (`arn:aws:iam::*:role/platform-execution`), but:

1. Must pass the same `Role` tag (`Reader` or `Deployer`) when assuming downstream roles
2. The `ForAllValues:StringLike` condition on `aws:TagKeys` enforces transitive tag passing

This creates a chain of trust where permissions are propagated from the initial assumption through to the target account.

## Tagging

The following tags are automatically applied to both roles:
- `PlatformManaged = true`

Additional tags can be merged via the `tags` variable.

## Integration with credential_process

The `credential_process` script should call `AssumeRole` with the appropriate tags:

```bash
# For read-only access
aws sts assume-role \
  --role-arn arn:aws:iam::<platform-account>:role/platform-reader-admin \
  --role-session-name my-session \
  --tags Key=Role,Value=Reader

# For deployment access
aws sts assume-role \
  --role-arn arn:aws:iam::<platform-account>:role/platform-deployer-admin \
  --role-session-name my-session \
  --tags Key=Role,Value=Deployer
```

## Related Modules

- **platform-execution** - The downstream execution roles in target accounts that these roles assume
