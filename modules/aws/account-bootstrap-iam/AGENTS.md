# Account Bootstrap IAM Module - Agent Guide

## Purpose

This module creates the `platform-execution` IAM role in sibling accounts. This role is the target that the Platform Account's jump host roles (`platform-reader-admin` and `platform-deployer-admin`) assume when managing infrastructure.

## Context

- **Provider:** Must be executed with credentials in the **Target (Sibling) Account** - typically via the `management-admin` role created by the `account` module
- **Session Tagging:** Enforces `Role=Reader` or `Role=Deployer` permissions based on tags passed during `AssumeRole`
- **Upstream Source:** `platform-reader-admin` and `platform-deployer-admin` from the Platform Account

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `platform_account_id` | `string` | Yes | AWS Account ID of the Platform Account. |
| `organization` | `string` | Yes | Organization name (e.g., `acme`). Used for tagging. |
| `namespace` | `string` | Yes | Namespace (e.g., `core`, `analytics`). Used for tagging. |
| `environment` | `string` | Yes | Environment. Must be: `staging`, `production`, or `global`. |
| `tags` | `map(string)` | No | Additional tags to merge. |

## Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of `platform-execution` |
| `role_name` | Name of `platform-execution` |

## Tagging

The following tags are automatically applied:
- `PlatformManaged = true` - Critical for SCP/Permission Boundary protection (cannot be overridden)
- `Organization`, `Namespace`, `Environment` - Standard labels for consistency (cannot be overridden)

**Important:** System tags are merged AFTER `var.tags` to prevent override attempts.

## Security Model

### Trust Policy (Privilege Escalation Prevention)

Separate trust statements for Reader and Deployer:

**Reader (`platform-reader-admin`):**
- Actions: `sts:AssumeRole` only
- Cannot tag sessions (prevents escalation)

**Deployer (`platform-deployer-admin`):**
- Actions: `sts:AssumeRole`, `sts:TagSession`
- Conditions:
  - `aws:RequestTag/Role` must equal `Deployer`
  - `aws:TagKeys` restricted to `["Role"]` only

### Permissions

1. **ReadOnly**: AWS managed `ReadOnlyAccess` policy attached unconditionally
2. **Admin**: Inline policy granting `*:*` only when `aws:PrincipalTag/Role = Deployer`

## Scope Boundaries

This module **only** creates the platform-execution role. The following are **out of scope**:

- Jump host roles in the Platform Account (use `platform-bootstrap-iam`)
- Account creation (use `account`)
- Account baseline configuration (use `account-baseline`)

## Deployment Order

1. Create account with `account` module (Management Account context)
2. Create jump host roles with `platform-bootstrap-iam` (Platform Account context)
3. Deploy this module into sibling accounts (Target Account context via `management-admin` role)

## Key Implementation Details

- Uses `aws_iam_policy_document` data sources for policy definitions
- Inline policy via `aws_iam_role_policy` for conditional admin access
- Managed policy attachment via `aws_iam_role_policy_attachment` for ReadOnly
- No provider configuration in module (child module pattern)
