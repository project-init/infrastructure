variable "reader_session_duration" {
  description = "Session duration for Reader permission set (ISO 8601 duration format)"
  type        = string
  default     = "PT8H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.reader_session_duration))
    error_message = "reader_session_duration must be an ISO 8601 duration between PT1H and PT12H (e.g., PT8H)."
  }
}

variable "operator_session_duration" {
  description = "Session duration for Operator permission set (ISO 8601 duration format)"
  type        = string
  default     = "PT8H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.operator_session_duration))
    error_message = "operator_session_duration must be an ISO 8601 duration between PT1H and PT12H (e.g., PT8H)."
  }
}

variable "admin_session_duration" {
  description = "Session duration for Admin permission set (ISO 8601 duration format, shorter for security)"
  type        = string
  default     = "PT1H"

  validation {
    condition     = can(regex("^PT([1-9]|1[0-2])H$", var.admin_session_duration))
    error_message = "admin_session_duration must be an ISO 8601 duration between PT1H and PT12H (e.g., PT1H)."
  }
}

variable "tags" {
  description = "Additional tags to apply to resources (merged with default tags)"
  type        = map(string)
  default     = {}
}
