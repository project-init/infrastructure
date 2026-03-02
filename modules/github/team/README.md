# GitHub Team Module

This module creates a GitHub team, configures its settings (such as privacy), and manages team memberships for users at specified roles (e.g., maintainers and regular members). It enforces a flat structure by not supporting nested/child teams.

## Usage

```hcl
module "example_team" {
  source = "./modules/github/team"

  name        = "example-team"
  description = "An example GitHub team"
  privacy     = "secret"

  maintainers = ["alice", "bob"]
  members     = ["charlie", "david"]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the team. | `string` | n/a | yes |
| description | A description of the team. | `string` | `null` | no |
| privacy | The level of privacy for the team. Valid values are secret or closed. | `string` | `"secret"` | no |
| maintainers | A list of GitHub usernames to be added as maintainers. | `list(string)` | `[]` | no |
| members | A list of GitHub usernames to be added as regular members. | `list(string)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the team |
| node_id | The Node ID of the team |

## Providers

| Name | Version |
|------|---------|
| github | ~> 6.0 |