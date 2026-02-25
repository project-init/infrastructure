# Module: team

## Overview
This module creates a GitHub team, configures its settings (such as privacy), and manages team memberships for users at specified roles (e.g., maintainers and regular members). It enforces a flat structure by not supporting nested/child teams.

## Resources Created
| Resource | Description |
|----------|-------------|
| `github_team` | The GitHub team resource itself |
| `github_team_membership` | Manages the addition of individual users to the team |

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name` | `string` | n/a | yes | The name of the team. |
| `description` | `string` | `null` | no | A description of the team. |
| `privacy` | `string` | `"secret"` | no | The level of privacy for the team. Valid values are `secret` or `closed`. |
| `maintainers` | `list(string)` | `[]` | no | A list of GitHub usernames to be added as maintainers. |
| `members` | `list(string)` | `[]` | no | A list of GitHub usernames to be added as regular members. |

## Outputs
| Name | Description |
|------|-------------|
| `id` | The ID of the team |
| `node_id` | The Node ID of the team |

## Dependencies
- **Provider Requirements**: `github` ~> 6.0
- No other module dependencies.

## Naming Convention
Team names are created exactly as provided in the `name` variable (no automatic prefixes).

## Usage Example
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

## Implementation Notes
- The module should use `for_each` on the `github_team_membership` resource to iterate over the provided lists of `maintainers` and `members`.
- The `role` argument in `github_team_membership` must be set appropriately (`maintainer` vs `member`) depending on which list the user is in.
- Nested/child teams are explicitly unsupported; do not include a `parent_team_id` variable.

## Out of Scope
- Management of child/nested teams.
- Management of repository access for the team.
- Team sync with external Identity Providers (IdP).
