# Platform Bootstrap IAM Module - Agent Guide

## Purpose

This module creates the "Jump Host" IAM roles (`platform-reader-admin` and `platform-deployer-admin`) in the Platform Account. These roles are the entry point for users to manage infrastructure across the organization via session tagging.

## Context

- **Provider:** Must be executed with credentials in the **Platform Account**
- **Session Tagging:** Enforces `Role=Reader` or `Role=Deployer` tags that propagate downstream
- **Downstream Target:** Both roles can assume `arn:aws:iam::*:role/platform-execution`

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `allowed_principals` | `list(string)` | Yes | ARNs of SSO Roles or Users allowed to assume these roles. |
| `tags` | `map(string)` | No | Additional tags to merge. |

## Outputs

| Name | Description |
|------|-------------|
| `reader_role_arn` | ARN of `platform-reader-admin` |
| `deployer_role_arn` | ARN of `platform-deployer-admin` |

## Tagging

- `PlatformManaged = true` is automatically applied to both roles
- Additional tags from `var.tags` are merged

## Security Model

### Trust Policy Conditions

Both roles require the caller to pass a session tag matching their permission level:

- `platform-reader-admin`: `aws:RequestTag/Role = Reader`
- `platform-deployer-admin`: `aws:RequestTag/Role = Deployer`

### Permissions Policy Conditions

When assuming downstream `platform-execution` roles:

1. Must pass `aws:RequestTag/Role` matching the role's level (`Reader` or `Deployer`)
2. `ForAllValues:StringLike` on `aws:TagKeys` enforces the `Role` tag is passed transitively

## Scope Boundaries

This module **only** creates the jump host roles in the Platform Account. The following are **out of scope**:

- `platform-execution` roles in target accounts (separate module)
- The `credential_process` script configuration
- Any downstream account resources

## Key Implementation Details

- Uses `aws_iam_policy_document` data sources for trust and permissions policies
- Inline policies via `aws_iam_role_policy` (not managed policies)
- Resource target is wildcard: `arn:aws:iam::*:role/platform-execution`
