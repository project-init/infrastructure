# Identity Center Module

Configures AWS IAM Identity Center permission sets for an AWS Organization. Establishes three access tiers (Reader, Operator, Admin) with a permission boundary that enforces security guardrails across all non-admin access.

## Why This Module Exists

Identity Center (formerly AWS SSO) is the standard way to manage human access to AWS accounts. This module solves several problems:

1. **Consistent access tiers** - Rather than ad-hoc permission sets per account, we define three standard tiers that work across all accounts
2. **Privilege escalation prevention** - Operators can create IAM roles, but those roles automatically inherit the same restrictions via a forced permission boundary
3. **Dangerous operation guardrails** - VPC mutations, organization changes, and IAM user creation are blocked for non-admin access

The permission boundary creates a "ceiling" that applies recursively: any role created by an Operator (or by a role created by an Operator, and so on) cannot exceed the boundary's permissions.

## Access Tiers

| Tier | Use Case | Restrictions |
|------|----------|--------------|
| **Reader** | Debugging, auditing, exploring | Read-only via ViewOnlyAccess; boundary adds guardrails |
| **Operator** | Day-to-day development and operations | Full access except VPC/Org mutations; can create roles but they inherit the boundary |
| **Admin** | Break-glass, infrastructure changes | No restrictions; 1-hour session default |

## Usage

```hcl
module "identity_center" {
  source = "./modules/identity-center"

  # Optional: Override default session durations
  reader_session_duration   = "PT8H"  # 8 hours
  operator_session_duration = "PT8H"  # 8 hours
  admin_session_duration    = "PT1H"  # 1 hour

  tags = {
    Environment = "production"
  }
}
```

## Prerequisites

- Must be executed with credentials from the **Management Account**
- AWS Organizations must be enabled
- Identity Center must be enabled (via Console or separate module)

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `reader_session_duration` | `string` | `"PT8H"` | No | Session duration for Reader (ISO 8601) |
| `operator_session_duration` | `string` | `"PT8H"` | No | Session duration for Operator (ISO 8601) |
| `admin_session_duration` | `string` | `"PT1H"` | No | Session duration for Admin (ISO 8601) |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply |

## Outputs

| Name | Description |
|------|-------------|
| `identity_center_instance_arn` | ARN of the Identity Center instance |
| `identity_store_id` | ID of the Identity Store (for group/user lookups) |
| `permission_set_arns` | Map of permission set names to ARNs |
| `permission_boundary_policy_document` | JSON policy to create in each target account |
| `permission_boundary_policy_name` | Expected policy name (`default-permission-boundary`) |

## Permission Boundary

The module outputs a permission boundary policy document that **must be created in each target account** before Reader/Operator assignments will work. This is typically done by the account-baseline module:

```hcl
resource "aws_iam_policy" "permission_boundary" {
  name   = module.identity_center.permission_boundary_policy_name
  policy = module.identity_center.permission_boundary_policy_document
}
```

The boundary denies:
- **VPC mutations** - CreateVpc, DeleteVpc, CreateSubnet, etc.
- **Organization actions** - LeaveOrganization, CreateAccount, policy changes, etc.
- **IAM user creation** - CreateUser, DeleteUser
- **Boundary tampering** - PutRolePermissionsBoundary, DeleteRolePermissionsBoundary
- **Role creation without boundary** - CreateRole is denied unless the new role also has the boundary attached

This last rule is critical: it creates recursive protection. An Operator cannot escape the boundary by creating a role without it.

## What This Module Does NOT Do

- **Identity Provider setup** - Google Workspace, Okta, Azure AD configuration is handled separately
- **SCIM provisioning** - User/group sync is configured externally
- **Account assignments** - Assigning permission sets to groups/users is a separate concern
- **Creating the boundary in accounts** - The account-baseline module handles this

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_ssoadmin_permission_set.reader` | Reader permission set |
| `aws_ssoadmin_permission_set.operator` | Operator permission set |
| `aws_ssoadmin_permission_set.admin` | Admin permission set |
| `aws_ssoadmin_managed_policy_attachment.*` | AWS managed policy attachments |
| `aws_ssoadmin_permissions_boundary_attachment.reader` | Boundary attachment for Reader |
| `aws_ssoadmin_permissions_boundary_attachment.operator` | Boundary attachment for Operator |
