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
| `authorization_patterns` | `list(object)` | `[]` | Yes | List of authorization patterns to configure the trust policy. |
| `inline_policies` | `list(object)` | `[]` | No | List of inline policies to attach to the role. |
| `managed_policy_arns` | `list(string)` | `[]` | No | List of IAM managed policy ARNs to attach to the role. |
| `tags` | `map(string)` | `{}` | No | Tags to apply to the IAM role. |

### `authorization_patterns` Structure

```hcl
variable "authorization_patterns" {
  type = list(object({
    sid = string
    claims = object({
      repositories       = list(string)
      repository_owners  = optional(list(string))
      refs               = optional(list(string))
      environments       = optional(list(string))
      job_workflow_refs  = optional(list(string))
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
- `aws` provider >= 4.0.0
- `modules/aws/iam-role` module: Used internally to create the IAM role.

## Usage Example

```hcl
module "github_actions_role" {
  source = "./modules/aws/github-actions-role"

  name = "github-actions-deploy-role"
  description = "Role for GitHub Actions deployments"

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
