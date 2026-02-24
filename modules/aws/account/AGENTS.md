# Account Module - Agent Guide

## Purpose

This module creates new AWS accounts within an AWS Organization. It is **strictly responsible** for the `aws_organizations_account` resource and ensuring the initial bootstrap role exists.

## Context

- **Provider:** Must be executed with credentials from the **Management Account**
- **Bootstrap Role:** Establishes an IAM role (`role_name`) that allows the Management Account to assume control for subsequent bootstrapping steps

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `organization` | `string` | Yes | Organization name (e.g., `acme`). Used for tagging only. |
| `namespace` | `string` | Yes | Namespace for the account (e.g., `core`, `analytics`). Part of account name. |
| `environment` | `string` | Yes | Environment. **Must be one of:** `staging`, `production`, `global`. |
| `email` | `string` | Yes | Root email address for the new account. |
| `role_name` | `string` | No | Bootstrap IAM role name. Default: `management-admin`. |
| `parent_id` | `string` | No | Parent Organizational Unit ID or Root ID. |
| `tags` | `map(string)` | No | Additional tags to merge. |

## Outputs

| Name | Description |
|------|-------------|
| `account_id` | The AWS Account ID of the newly created account. |
| `account_arn` | The ARN of the newly created account. |
| `organization_role_arn` | Full ARN of the bootstrap role: `arn:aws:iam::<id>:role/<role_name>`. |
| `parent_id` | The Parent ID the account was placed in. |

## Naming & Tagging

- **Account Name:** `<namespace>-<environment>` (e.g., `analytics-production`)
- **Tags Applied:**
  - `Organization` = `<organization>`
  - `Namespace` = `<namespace>`
  - `Environment` = `<environment>`
  - Plus any tags from `var.tags`

## Scope Boundaries

This module **only** creates the account. The following are **out of scope** and should be handled by a separate `account-baseline` module:

- IAM account alias
- IAM password policy
- CloudTrail, GuardDuty, SecurityHub
- Default VPC removal
- Any resource requiring a provider in the target account

**Why?** Terraform evaluates provider configurations before resources are created. The bootstrap role doesn't exist until after the account is created, so a two-stage apply is required.

## Validation Rules

- `environment` must be one of: `staging`, `production`, `global`
