variable "name" {
  type        = string
  description = "The exact name of the GitHub repository to be created."
}

variable "description" {
  type        = string
  description = "A short description of the repository."
  default     = ""
}

variable "visibility" {
  type        = string
  description = "The visibility of the repository (e.g., \"public\", \"private\", \"internal\")."
  default     = "private"
  validation {
    condition     = contains(["public", "private", "internal"], var.visibility)
    error_message = "Visibility must be one of: public, private, internal."
  }
}

variable "has_issues" {
  type        = bool
  description = "Whether to enable GitHub Issues for the repository."
  default     = true
}

variable "has_projects" {
  type        = bool
  description = "Whether to enable GitHub Projects for the repository."
  default     = true
}

variable "has_wiki" {
  type        = bool
  description = "Whether to enable GitHub Wiki for the repository."
  default     = true
}

variable "required_pull_request_reviews" {
  type        = number
  description = "The number of required approving reviews for pull requests targeting main."
  default     = 2
}

variable "required_status_checks" {
  type        = list(string)
  description = "A list of status checks that must pass before merging into main."
  default     = []
}

variable "collaborator_permissions" {
  type        = map(string)
  description = "A map of usernames to permission levels (e.g., \"pull\", \"push\", \"maintain\", \"admin\", \"triage\")."
  default     = {}
}

variable "team_permissions" {
  type        = map(string)
  description = "A map of team slugs or IDs to permission levels (e.g., \"pull\", \"push\", \"maintain\", \"admin\")."
  default     = {}
}
