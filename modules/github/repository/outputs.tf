output "repository_id" {
  description = "The unique ID of the created repository."
  value       = github_repository.this.repo_id
}

output "repository_full_name" {
  description = "The full name of the repository (format: org/repo)."
  value       = github_repository.this.full_name
}

output "repository_html_url" {
  description = "The HTML URL to access the repository on GitHub."
  value       = github_repository.this.html_url
}

output "repository_ssh_clone_url" {
  description = "The URL to clone the repository via SSH."
  value       = github_repository.this.ssh_clone_url
}

output "repository_http_clone_url" {
  description = "The URL to clone the repository via HTTPS."
  value       = github_repository.this.http_clone_url
}
