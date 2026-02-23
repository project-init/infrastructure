# Module: identity-center

## Overview

This module enables and configures AWS IAM Identity Center for an AWS Organization. It creates three standard permission sets (Reader, Operator, Admin) with predefined policies and configurable session durations.

Identity provider configuration (e.g., Google Workspace, Okta, Azure AD) and SCIM provisioning are intentionally handled externally via Terramate components/bundles to allow flexibility across different identity providers.

## Resources Created

| Resource | Description |
|----------|-------------|
| `aws_ssoadmin_instance_access_control_attributes` | Identity Center instance configuration |
| `aws_ssoadmin_permission_set.reader` | Reader permission set with read-only access |
| `aws_ssoadmin_permission_set.operator` | Operator permission set with restricted admin access |
| `aws_ssoadmin_permission_set.admin` | Admin permission set with full access |
| `aws_ssoadmin_managed_policy_attachment.*` | AWS managed policy attachments for permission sets |
| `aws_ssoadmin_permissions_boundary_attachment.reader` | Permission boundary attachment for Reader |
| `aws_ssoadmin_permissions_boundary_attachment.operator` | Permission boundary attachment for Operator |

## Inputs

| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `reader_session_duration` | `string` | `"PT8H"` | No | Session duration for Reader permission set (ISO 8601 duration format) |
| `operator_session_duration` | `string` | `"PT8H"` | No | Session duration for Operator permission set (ISO 8601 duration format) |
| `admin_session_duration` | `string` | `"PT1H"` | No | Session duration for Admin permission set (ISO 8601 duration format, shorter for security) |
| `tags` | `map(string)` | `{}` | No | Additional tags to apply to resources (merged with default tags) |

## Outputs

| Name | Description |
|------|-------------|
| `identity_center_instance_arn` | ARN of the IAM Identity Center instance |
| `identity_store_id` | ID of the Identity Store associated with Identity Center |
| `permission_set_arns` | Map of permission set names to their ARNs (e.g., `{ "Reader" = "arn:...", "Operator" = "arn:...", "Admin" = "arn:..." }`) |
| `permission_boundary_policy_document` | JSON policy document for the permission boundary (to be created in target accounts) |
| `permission_boundary_policy_name` | Expected name for the permission boundary policy (for consistent ARN construction) |

## Dependencies

- **Provider**: Requires an AWS provider configured for the **management account** where AWS Organizations and Identity Center are enabled
- **AWS Organizations**: Must be enabled in the account
- **Downstream dependency**: The permission boundary policy must be created in each target account by the account baseline module before Reader/Operator permission set assignments will work

## Permission Set Definitions

### Reader

- **Purpose**: Read-only access across all AWS services
- **AWS Managed Policy**: `arn:aws:iam::aws:policy/ViewOnlyAccess`
- **Session Duration**: Configurable (default 8 hours)
- **Permission Boundary**: Required (consistent enforcement across all non-admin roles)

### Operator

- **Purpose**: Near-full admin access with explicit restrictions to prevent dangerous operations and privilege escalation
- **AWS Managed Policy**: `arn:aws:iam::aws:policy/AdministratorAccess`
- **Permission Boundary**: Required (enforces restrictions even on assumed roles)
- **Session Duration**: Configurable (default 8 hours)

**Permission Boundary Deny Policy:**

The following actions are denied via the permission boundary (applies to Reader, Operator, and all roles created in accounts):

1. **VPC Mutations**
   - `ec2:CreateVpc`
   - `ec2:DeleteVpc`
   - `ec2:CreateSubnet`
   - `ec2:DeleteSubnet`
   - `ec2:CreateInternetGateway`
   - `ec2:DeleteInternetGateway`
   - `ec2:AttachInternetGateway`
   - `ec2:DetachInternetGateway`
   - `ec2:CreateNatGateway`
   - `ec2:DeleteNatGateway`
   - `ec2:CreateVpcPeeringConnection`
   - `ec2:DeleteVpcPeeringConnection`
   - `ec2:AcceptVpcPeeringConnection`
   - `ec2:CreateTransitGateway`
   - `ec2:DeleteTransitGateway`
   - `ec2:ModifyVpcAttribute`

2. **Organization Actions**
   - `organizations:LeaveOrganization`
   - `organizations:DeleteOrganization`
   - `organizations:RemoveAccountFromOrganization`
   - `organizations:CreateAccount`
   - `organizations:CloseAccount`
   - `organizations:CreateOrganization`
   - `organizations:InviteAccountToOrganization`
   - `organizations:CreatePolicy`
   - `organizations:DeletePolicy`
   - `organizations:UpdatePolicy`
   - `organizations:AttachPolicy`
   - `organizations:DetachPolicy`

3. **IAM User Creation**
   - `iam:CreateUser`
   - `iam:DeleteUser`

4. **Privilege Escalation Prevention (forces permission boundary on all created roles)**
   - `iam:CreateRole` - Denied unless `iam:PermissionsBoundary` condition is set to the permission boundary ARN
   - `iam:PutRolePermissionsBoundary` - Denied (prevents modifying boundary on existing roles)
   - `iam:DeleteRolePermissionsBoundary` - Denied (prevents removing boundary from roles)

5. **Permission Boundary Policy Protection**
   - `iam:CreatePolicyVersion` - Denied on the boundary policy (prevents weakening restrictions)
   - `iam:DeletePolicy` - Denied on the boundary policy
   - `iam:DeletePolicyVersion` - Denied on the boundary policy
   - `iam:SetDefaultPolicyVersion` - Denied on the boundary policy

### Admin

- **Purpose**: Full administrative access with no restrictions
- **AWS Managed Policy**: `arn:aws:iam::aws:policy/AdministratorAccess`
- **Session Duration**: Configurable (default 1 hour for security)
- **Permission Boundary**: None

## Naming Convention

| Resource Type | Naming Pattern |
|---------------|----------------|
| Permission Sets | `Reader`, `Operator`, `Admin` |
| Permission Boundary Policy | `default-permission-boundary` |

## Tagging

The following tags are automatically applied to all taggable resources:

| Tag Key | Value |
|---------|-------|
| `ManagedBy` | `tofu` |

Additional tags can be provided via the `tags` input variable and will be merged with the defaults.

## Usage Example

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

# Outputs for downstream modules
output "permission_set_arns" {
  value = module.identity_center.permission_set_arns
}

output "identity_store_id" {
  value = module.identity_center.identity_store_id
}
```

## Implementation Notes

1. **Identity Center Instance**: The module uses `data.aws_ssoadmin_instances` to reference an existing Identity Center instance in the management account. Enabling Identity Center (`aws_ssoadmin_instance`) is not handled by this module and must be performed beforehand (for example via the AWS Console or a separate Terraform module) before applying this module.

2. **Permission Boundary Provisioning**: The permission boundary policy document is output by this module but must be created in each target account by a separate module (e.g., account baseline). The expected policy name is output to ensure consistent ARN construction:
   ```
   arn:aws:iam::<account-id>:policy/default-permission-boundary
   ```

3. **Permission Set ARN Pattern**: Permission sets reference the boundary using a wildcard account pattern:
   ```
   arn:aws:iam::*:policy/default-permission-boundary
   ```

4. **Forced Permission Boundary on All Roles**: When the permission boundary is deployed to target accounts, it enforces that ALL roles created in those accounts must also have the permission boundary attached. This creates a recursive protection that prevents privilege escalation - any role created by Reader, Operator, or any other role in the account will inherit the same restrictions.

5. **Provider Configuration**: This module assumes it receives a properly configured AWS provider for the management account. It does not handle provider configuration or role assumption internally.

6. **Idempotency**: The module is safe to apply multiple times. Permission sets are identified by name and will be updated rather than recreated.

7. **Session Duration Format**: Session durations use ISO 8601 duration format (e.g., `PT1H` for 1 hour, `PT8H` for 8 hours, `PT12H` for 12 hours). Valid range is 1-12 hours.

## Out of Scope

The following are intentionally NOT managed by this module:

- **Identity Provider Configuration**: External IdP setup (Google Workspace, Okta, Azure AD, etc.) is handled via Terramate components/bundles
- **SCIM Provisioning**: Automatic user/group sync configuration is handled via Terramate components/bundles
- **Groups and Users**: Managed via the external Identity Provider
- **Account Assignments**: Assigning permission sets to groups/users for specific accounts is handled by a downstream module
- **Permission Boundary in Target Accounts**: The boundary policy must be created in each account by the account baseline module
- **Service Control Policies (SCPs)**: Organization-wide guardrails are managed separately

## Future Considerations

The module structure supports future extension to allow custom permission sets in addition to the three standard tiers. This could be implemented via an additional input variable:

```hcl
variable "custom_permission_sets" {
  type = list(object({
    name                  = string
    description           = string
    session_duration      = string
    managed_policy_arns   = list(string)
    inline_policy         = optional(string)
    permission_boundary   = optional(string)
  }))
  default = []
}
```

This is noted for future implementation and is not part of the initial scope.
