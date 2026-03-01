variable "name" {
  description = "The name of the team."
  type        = string
}

variable "description" {
  description = "A description of the team."
  type        = string
  default     = null
}

variable "privacy" {
  description = "The level of privacy for the team. Valid values are secret or closed."
  type        = string
  default     = "secret"
  validation {
    condition     = contains(["secret", "closed"], var.privacy)
    error_message = "The privacy value must be 'secret' or 'closed'."
  }
}

variable "maintainers" {
  description = "A list of GitHub usernames to be added as maintainers."
  type        = list(string)
  default     = []
}

variable "members" {
  description = "A list of GitHub usernames to be added as regular members."
  type        = list(string)
  default     = []
}