# AWS Account Module

This module manages the creation of new AWS accounts within an AWS Organization.

## Overview

The module is responsible for:
- Creating new AWS accounts via `aws_organizations_account`
- Setting up an initial bootstrap IAM role for Management Account access
- Applying consistent naming and tagging conventions

## Prerequisites

- Must be executed with credentials from the **Management Account**
- AWS Organizations must be enabled in the Management Account

## Usage

```hcl
module "account" {
  source = "./modules/account"

  organization = "acme"
  namespace    = "analytics"
  environment  = "production"
  email        = "aws-analytics-prod@example.com"
  role_name    = "management-admin"
  parent_id    = "ou-xxxx-xxxxxxxx"

  tags = {
    Team    = "Platform"
    Project = "Infrastructure"
  }
}
```

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `organization` | `string` | - | Yes | The organization name (e.g., `acme`). Used for tagging. |
| `namespace` | `string` | - | Yes | The namespace for the account (e.g., `core`, `analytics`). Part of the account name. |
| `environment` | `string` | - | Yes | The environment. Must be one of: `staging`, `production`, `global`. |
| `email` | `string` | - | Yes | Root email address for the new account. |
| `role_name` | `string` | `"management-admin"` | No | The name of the IAM role to create in the new account for initial access. |
| `parent_id` | `string` | `null` | No | Parent Organizational Unit ID or Root ID. |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply. |

## Outputs

| Name | Description |
|------|-------------|
| `account_id` | The AWS Account ID of the newly created account. |
| `account_arn` | The ARN of the newly created account. |
| `organization_role_arn` | The complete ARN of the bootstrap role (`arn:aws:iam::<id>:role/<role_name>`). |
| `parent_id` | The Parent ID the account was placed in. |

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_organizations_account` | The AWS account within the Organization. |

## Naming Convention

Account names are constructed as `<namespace>-<environment>` (e.g., `analytics-production`).

## Tagging

The following tags are automatically applied to the account:
- `Organization` - from `var.organization`
- `Namespace` - from `var.namespace`
- `Environment` - from `var.environment`

Additional tags can be merged via the `tags` variable.

## Bootstrap Role

The `role_name` parameter specifies the IAM role created in the new account during account creation. This role:
- Grants `AdministratorAccess` to the Management Account
- Is used for initial bootstrapping and configuration
- Should be used to set up more granular access controls afterward

## Account Baseline Configuration

This module intentionally only creates the AWS account. Account-level configuration such as:
- IAM account alias
- IAM password policy
- CloudTrail, GuardDuty, SecurityHub
- Default VPC removal

Should be managed by a separate **account-baseline** module that:
1. Accepts a provider configured to assume the bootstrap role into the target account
2. Runs after the account has been created (two-stage apply or separate state)

This separation is necessary because:
- Terraform evaluates provider configurations before resource creation
- Child modules should not define their own provider configurations (deprecated pattern)
- The bootstrap role doesn't exist until the account is created
