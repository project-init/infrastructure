# Account Module Specification

## 1. Overview
**Purpose**: This module manages the creation of new AWS accounts within the AWS Organization. It is strictly responsible for the `aws_organizations_account` resource and ensuring the initial bootstrap role exists.

**Context**: 
- Must be executed with credentials from the **Management Account**.
- Establishes the initial `role_name` (Bootstrap Role) that allows the Management Account to assume control for subsequent bootstrapping steps.

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `namespace` | `string` | **Required** | The namespace for the account (e.g., `core`, `analytics`). Part of the account name. |
| `environment` | `string` | **Required** | The environment. Must be one of: `staging`, `production`, `global`. |
| `email` | `string` | **Required** | Root email address for the new account. |
| `role_name` | `string` | `"management-admin"` | The name of the IAM role to create in the new account for initial access. |
| `parent_id` | `string` | `null` | (Optional) Parent Organizational Unit ID or Root ID. |
| `tags` | `map(string)` | `{}` | Additional tags to apply. |

## 3. Resources

### `aws_organizations_account`
- **Name**: Constructed as `${var.namespace}-${var.environment}`.
- **Email**: `${var.email}`.
- **Role Name**: `${var.role_name}`.
- **Parent ID**: `${var.parent_id}` (if provided).
- **Tags**:
  - `Namespace`: `${var.namespace}`
  - `Environment`: `${var.environment}`
  - (Merge with `var.tags`)

## 4. Outputs

| Name | Description |
|------|-------------|
| `account_id` | The AWS Account ID of the newly created account. |
| `account_arn` | The ARN of the newly created account. |
| `organization_role_arn` | The complete ARN of the bootstrap role (`arn:aws:iam::<id>:role/<role_name>`). |
| `parent_id` | The Parent ID the account was placed in. |

## 5. Implementation Details

- **Validation**: Ensure `environment` input matches allowed values (`staging`, `production`, `global`).
- **Naming Convention**: Strictly enforce `<namespace>-<environment>`.
