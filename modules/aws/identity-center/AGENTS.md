# Identity Center Module

## Quick Reference

- **Purpose**: Configures IAM Identity Center permission sets (Reader, Operator, Admin) with permission boundary enforcement
- **Location**: `terraform/modules/identity-center/`
- **Provider**: Requires Management Account credentials

## Key Files

| File | Purpose |
|------|---------|
| `main.tf` | Permission sets, policy attachments, boundary attachments, boundary policy document |
| `variables.tf` | Session duration inputs, tags |
| `outputs.tf` | Instance ARN, identity store ID, permission set ARNs, boundary policy document |
| `versions.tf` | Terraform/provider version constraints |
| `SPEC.md` | Detailed specification with all denied actions listed |
| `README.md` | Human-focused documentation explaining the "why" |

## Architecture

```
Identity Center (Management Account)
├── Permission Sets
│   ├── Reader (ViewOnlyAccess + boundary)
│   ├── Operator (AdministratorAccess + boundary)
│   └── Admin (AdministratorAccess, no boundary)
└── Outputs boundary policy document
    └── Must be created in each target account by account-baseline
```

## Permission Boundary Enforcement

The boundary is attached to Reader and Operator permission sets and:
1. Denies VPC mutations, org actions, IAM user creation
2. Forces all created roles to have the same boundary attached
3. Prevents modifying/removing boundaries on existing roles
4. Prevents modifying/deleting the boundary policy itself

This creates recursive protection - roles created by Operator inherit the same restrictions.

## Common Tasks

### Adding a new denied action
Edit the `data "aws_iam_policy_document" "permission_boundary"` block in `main.tf`. Add to the appropriate statement or create a new one.

### Changing session durations
Modify defaults in `variables.tf` or pass values when calling the module.

### Adding a new permission set
Add a new `aws_ssoadmin_permission_set` resource, corresponding `aws_ssoadmin_managed_policy_attachment`, and optionally a boundary attachment. Update the `permission_set_arns` output map.

## Dependencies

- **Upstream**: Identity Center must be enabled in Management Account
- **Downstream**: `account-baseline` module must create the `default-permission-boundary` IAM policy in each account using the `permission_boundary_policy_document` output
