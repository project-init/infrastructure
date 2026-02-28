# Module: github-actions-role

## Overview
This module creates an AWS IAM role specifically configured to be assumed by GitHub Actions via Web Identity Federation (OIDC). It takes advantage of the newly supported STS claims (`repository`, `repository_owner`, `ref`, `environment`, `job_workflow_ref`) to allow fine-grained access control based on the GitHub context, moving beyond the traditional `aud` and `sub` constraints.

## Resources Created
| Resource | Description |
|----------|-------------|
| `module.iam_role` | Instantiates the `modules/aws/iam-role` module to create the IAM role, automatically applying the correct permission boundary and organizational standards. |

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | `null` | No | Exact name for the IAM role. Conflicts with `name_prefix`. |
| `name_prefix` | `string` | `null` | No | Prefix for the IAM role name. Conflicts with `name`. |
| `description` | `string` | n/a | Yes | Description of the IAM role. |
| `oidc_provider_arn` | `string` | `""` | No | ARN of the GitHub Actions OIDC provider. If not provided, it defaults to `arn:aws:iam::${account_id}:oidc-provider/token.actions.githubusercontent.com`. |
| `authorization_patterns` | `list(object)` | `[]` | Yes | List of authorization patterns to configure the trust policy. See specific structure below. |
| `inline_policies` | `map(string)` | `{}` | No | Map of inline policy names to JSON strings to attach to the role. |
| `managed_policy_arns` | `list(string)` | `[]` | No | List of IAM managed policy ARNs to attach to the role. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to the IAM role. |

### `authorization_patterns` Structure
```hcl
variable "authorization_patterns" {
  type = list(object({
    sid = string
    claims = object({
      repositories       = optional(list(string))
      repository_owners  = optional(list(string))
      refs               = optional(list(string))
      environments       = optional(list(string))
      job_workflow_refs  = optional(list(string))
      aud                = optional(list(string))
      sub                = optional(list(string))
    })
  }))
}
```

## Outputs
| Name | Description |
|------|-------------|
| `role_arn` | The ARN of the created IAM role. |
| `role_name` | The name of the created IAM role. |

## Dependencies
- `aws` provider >= 4.0.0 (or version supporting recent STS claims).
- `modules/aws/iam-role` module: Used internally to create the IAM role and ensure required organizational standards (like permission boundaries) are correctly applied.
- Requires `data.aws_caller_identity.current` to construct the default OIDC provider ARN if not explicitly provided.

## Naming Convention
The module will respect the provided `name` or `name_prefix` variables. Standard Terraform naming practices should be followed. 

## Tagging
Tags passed through the `tags` variable will be automatically applied to the underlying IAM role.

## Usage Example
```hcl
module "github_actions_role" {
  source = "./modules/aws/github-actions-role"

  name = "github-actions-deploy-role"

  authorization_patterns = [
    {
      sid = "AllowMainBranchDeploy"
      claims = {
        repositories = ["my-org/my-repo"]
        refs         = ["refs/heads/main"]
        environments = ["production"]
      }
    }
  ]

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
}
```

## Implementation Notes
- **IAM Role Creation:** The module must use `../iam-role` (or the equivalent path to `modules/aws/iam-role`) rather than creating an `aws_iam_role` resource directly. Pass the `name`, `name_prefix`, `inline_policies`, `managed_policy_arns`, and `tags` to this child module.
- **Trust Policy Generation:** The module needs to generate an `aws_iam_policy_document` for the role's `assume_role_policy` and pass this document's JSON to the `iam-role` module.
- Each element in `authorization_patterns` corresponds to an individual `statement` within the trust policy.
- For a given statement, all specified claims within the `claims` object should be ANDed together.
- The condition operator to use for the claims is `ForAnyValue:StringLike` as specifically requested by the requirements, allowing wildcard matching (e.g., `repositories = ["my-org/*"]`). The condition keys map directly to `token.actions.githubusercontent.com:<claim_name>`.
- The `Principal` should always be `Federated` with the `oidc_provider_arn`.
- The `Action` is `sts:AssumeRoleWithWebIdentity`.

## Out of Scope
- This module explicitly does **not** create the GitHub OIDC Identity Provider (`aws_iam_openid_connect_provider`) in AWS. It assumes this baseline resource is managed externally.
