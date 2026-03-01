mock_provider "github" {}

run "test_team_creation" {
  command = plan

  variables {
    name        = "test-team"
    description = "A test team"
    privacy     = "secret"
    maintainers = ["test-maintainer-1"]
    members     = ["test-member-1", "test-member-2"]
  }

  assert {
    condition     = github_team.this.name == "test-team"
    error_message = "Team name did not match expected."
  }

  assert {
    condition     = github_team.this.privacy == "secret"
    error_message = "Team privacy did not match expected."
  }

  assert {
    condition     = length(github_team_membership.maintainers) == 1
    error_message = "Expected 1 maintainer."
  }

  assert {
    condition     = length(github_team_membership.members) == 2
    error_message = "Expected 2 members."
  }
}