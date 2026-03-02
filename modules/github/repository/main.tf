resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = var.visibility

  has_issues   = var.has_issues
  has_projects = var.has_projects
  has_wiki     = var.has_wiki

  # Archiving instead of destroying
  archive_on_destroy = var.archive_on_destroy

  # Initialization for branch protections
  auto_init = true

  # Merge Strategies
  allow_squash_merge = true
  allow_merge_commit = false
  allow_rebase_merge = false
}

resource "github_branch_default" "main" {
  repository = github_repository.this.name
  branch     = "main"

  depends_on = [
    github_repository.this
  ]
}

resource "github_branch_protection" "main" {
  repository_id = github_repository.this.node_id
  pattern       = "main"

  # Enforce protection rules on the main branch
  enforce_admins = true

  required_pull_request_reviews {
    required_approving_review_count = var.required_pull_request_reviews
  }

  dynamic "required_status_checks" {
    for_each = length(var.required_status_checks) > 0 ? [1] : []
    content {
      strict   = true
      contexts = var.required_status_checks
    }
  }

  depends_on = [
    github_branch_default.main
  ]
}

resource "github_repository_collaborator" "this" {
  for_each = var.collaborator_permissions

  repository = github_repository.this.name
  username   = each.key
  permission = each.value
}

resource "github_team_repository" "this" {
  for_each = var.team_permissions

  repository = github_repository.this.name
  team_id    = each.key
  permission = each.value
}
