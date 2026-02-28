# Module: repository

## Overview
This Terraform module provisions a GitHub repository with built-in security and branch protection standards. It ensures the repository is initialized with a `main` branch and enforces pull request reviews before merging into `main`. By default, it creates a private repository and mandates squash merges, disabling all other merge strategies.

## Resources Created
| Resource | Description |
|----------|-------------|
| `github_repository` | The primary GitHub repository resource. |
| `github_branch_default` | Ensures the default branch is set to `main`. |
| `github_branch_protection` | Configures branch protections for the `main` branch, enforcing PR reviews and status checks. |
| `github_repository_collaborator` | Grants access to individual users at specified permission levels. |
| `github_team_repository` | Grants access to GitHub teams at specified permission levels. |

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | - | Yes | The exact name of the GitHub repository to be created. |
| `description` | `string` | `""` | No | A short description of the repository. |
| `visibility` | `string` | `"private"` | No | The visibility of the repository (e.g., "public", "private", "internal"). |
| `has_issues` | `bool` | `true` | No | Whether to enable GitHub Issues for the repository. |
| `has_projects` | `bool` | `true` | No | Whether to enable GitHub Projects for the repository. |
| `has_wiki` | `bool` | `true` | No | Whether to enable GitHub Wiki for the repository. |
| `required_pull_request_reviews` | `number` | `2` | No | The number of required approving reviews for pull requests targeting `main`. |
| `required_status_checks` | `list(string)` | `[]` | No | A list of status checks that must pass before merging into `main`. |
| `collaborator_permissions` | `map(string)` | `{}` | No | A map of usernames to permission levels (e.g., "pull", "push", "maintain", "admin", "triage"). |
| `team_permissions` | `map(string)` | `{}` | No | A map of team slugs or IDs to permission levels (e.g., "pull", "push", "maintain", "admin"). |

## Outputs
| Name | Description |
|------|-------------|
| `repository_id` | The unique ID of the created repository. |
| `repository_full_name` | The full name of the repository (format: `org/repo`). |
| `repository_html_url` | The HTML URL to access the repository on GitHub. |
| `repository_ssh_clone_url` | The URL to clone the repository via SSH. |
| `repository_http_clone_url` | The URL to clone the repository via HTTPS. |

## Dependencies
- Provider: `hashicorp/github` version `>= 5.0` (or similar recent version).
- The module must run with credentials that have sufficient permissions to create repositories and branch protections in the target GitHub organization/account.

## Naming Convention
The repository name is taken exactly as provided via the `name` input variable, without any enforced prefixes or suffixes.

## Tagging
Topics (tags) can be optionally supported if added to the inputs, but no default tags are automatically applied at this level unless specified. (Consider adding `topics` as an optional input if needed).

## Usage Example
```hcl
module "github_repo" {
  source = "./modules/github/repository"

  name        = "my-new-service"
  description = "A new microservice"
  visibility  = "private"
  
  has_issues   = true
  has_projects = false
  has_wiki     = false

  required_pull_request_reviews = 2
  required_status_checks        = ["ci/circleci: build", "security/snyk"]

  collaborator_permissions = {
    "alice" = "admin"
    "bob"   = "push"
  }

  team_permissions = {
    "backend-devs" = "push"
    "security"     = "maintain"
  }
}
```

## Implementation Notes
- **Initialization**: To pre-create the `main` branch, the `github_repository` resource must have `auto_init = true`. This will automatically create an initial commit (usually a README or .gitignore).
- **Merge Strategies**: The module must enforce squash merges by setting `allow_squash_merge = true`, `allow_merge_commit = false`, and `allow_rebase_merge = false` on the `github_repository` resource.
- **Ordering Requirements**: The `github_branch_protection` resource must depend on the creation of the `main` branch, which happens during repository creation when `auto_init = true`.
- **Permissions**: The module will use `for_each` over `collaborator_permissions` and `team_permissions` to create `github_repository_collaborator` and `github_team_repository` resources, assigning the specified roles.

## Out of Scope
- This module intentionally does NOT handle the creation of GitHub Environments.
- This module intentionally does NOT handle the creation of GitHub Teams or Users.
- This module intentionally does NOT handle the creation of Webhooks.
- This module intentionally does NOT handle the provisioning of Deploy Keys or Action Secrets (unless explicitly added later).
