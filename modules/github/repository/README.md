# GitHub Repository Module

This OpenTofu/Terraform module provisions a GitHub repository with built-in security and branch protection standards.

## Features

- Creates a GitHub repository (private by default)
- Initializes the repository with a `main` default branch
- Enforces branch protection rules on `main`
- Requires squash merges, disabling merge commits and rebase merges
- Enforces pull request reviews and status checks
- Configures individual collaborator and team permissions

## Usage

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

## Providers

| Name | Version |
|------|---------|
| `github` | `>= 5.0.0` |
