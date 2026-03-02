#------------------------------------------------------------------------------
# GitHub Repository Module Tests
#------------------------------------------------------------------------------

mock_provider "github" {}

run "valid_repository_creation" {
  command = plan

  variables {
    name                          = "test-service"
    description                   = "A test microservice"
    visibility                    = "private"
    has_issues                    = true
    has_projects                  = false
    has_wiki                      = false
    required_pull_request_reviews = 1
    required_status_checks        = ["ci/test"]

    collaborator_permissions = {
      "alice" = "admin"
      "bob"   = "push"
    }

    team_permissions = {
      "dev-team" = "push"
    }
  }

  assert {
    condition     = github_repository.this.name == "test-service"
    error_message = "Repository name should match input."
  }

  assert {
    condition     = github_repository.this.visibility == "private"
    error_message = "Repository visibility should be private."
  }

  assert {
    condition     = github_branch_default.main.branch == "main"
    error_message = "Default branch should be main."
  }

  assert {
    condition     = github_branch_protection.main.pattern == "main"
    error_message = "Branch protection should target main."
  }

  assert {
    condition     = github_branch_protection.main.required_pull_request_reviews[0].required_approving_review_count == 1
    error_message = "Required approving reviews should match input."
  }

  assert {
    condition     = contains(github_branch_protection.main.required_status_checks[0].contexts, "ci/test")
    error_message = "Required status checks should match input."
  }

  assert {
    condition     = github_repository_collaborator.this["alice"].permission == "admin"
    error_message = "Collaborator alice should have admin permission."
  }

  assert {
    condition     = github_team_repository.this["dev-team"].permission == "push"
    error_message = "Team dev-team should have push permission."
  }
}

run "invalid_visibility" {
  command = plan

  variables {
    name       = "test-service"
    visibility = "super-secret"
  }

  expect_failures = [
    var.visibility
  ]
}

run "no_status_checks" {
  command = plan

  variables {
    name                   = "test-service"
    required_status_checks = []
  }

  assert {
    condition     = length(github_branch_protection.main.required_status_checks) == 0
    error_message = "Should not have required_status_checks block when empty."
  }
}
