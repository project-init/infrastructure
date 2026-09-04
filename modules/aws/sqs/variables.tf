variable "name" {
  description = "Name of the standard SQS queue and prefix for related resources."
  type        = string
  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]{1,80}$", var.name))
    error_message = "name must contain 1-80 letters, numbers, underscores, or hyphens."
  }
}

variable "tags" {
  description = "Additional tags applied to taggable resources. Caller values take precedence."
  type        = map(string)
  default     = {}
}

variable "message_retention_seconds" {
  description = "How long the source queue retains messages."
  type        = number
  default     = 345600
  validation {
    condition     = var.message_retention_seconds >= 60 && var.message_retention_seconds <= 1209600
    error_message = "message_retention_seconds must be between 60 and 1209600."
  }
}

variable "visibility_timeout_seconds" {
  description = "How long a received message remains hidden from other consumers."
  type        = number
  default     = 30
  validation {
    condition     = var.visibility_timeout_seconds >= 0 && var.visibility_timeout_seconds <= 43200
    error_message = "visibility_timeout_seconds must be between 0 and 43200."
  }
}

variable "max_message_size_bytes" {
  description = "Maximum message body size in bytes."
  type        = number
  default     = 262144
  validation {
    condition     = var.max_message_size_bytes >= 1024 && var.max_message_size_bytes <= 262144
    error_message = "max_message_size_bytes must be between 1024 and 262144."
  }
}

variable "delay_seconds" {
  description = "Default delivery delay for messages."
  type        = number
  default     = 0
  validation {
    condition     = var.delay_seconds >= 0 && var.delay_seconds <= 900
    error_message = "delay_seconds must be between 0 and 900."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long-polling wait time for ReceiveMessage calls."
  type        = number
  default     = 0
  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20."
  }
}

variable "enable_dlq" {
  description = "Whether the module creates and attaches a dead-letter queue."
  type        = bool
  default     = true
}

variable "max_receive_count" {
  description = "Number of receives before SQS moves a message to the configured DLQ."
  type        = number
  default     = 5
}

variable "dlq_message_retention_seconds" {
  description = "How long the module-created dead-letter queue retains messages."
  type        = number
  default     = 1209600
  validation {
    condition     = var.dlq_message_retention_seconds >= 60 && var.dlq_message_retention_seconds <= 1209600
    error_message = "dlq_message_retention_seconds must be between 60 and 1209600."
  }
}

variable "dlq_arn" {
  description = "ARN of an existing standard SQS queue to use as the DLQ when enable_dlq is false."
  type        = string
  default     = null
  validation {
    condition     = var.dlq_arn == null || can(regex("^arn:[^:]+:sqs:[^:]+:[0-9]{12}:[a-zA-Z0-9_-]{1,80}$", var.dlq_arn))
    error_message = "dlq_arn must be a valid standard SQS queue ARN when supplied."
  }
}

variable "kms_key_arn" {
  description = "ARN of an existing customer-managed KMS key used by the source queue and module-created DLQ."
  type        = string
  default     = null
}

variable "create_kms_key" {
  description = "Whether to create a dedicated customer-managed KMS key when kms_key_arn is null."
  type        = bool
  default     = true
}

variable "kms_key_deletion_window_in_days" {
  description = "Deletion window for the module-created KMS key."
  type        = number
  default     = 30
  validation {
    condition     = var.kms_key_deletion_window_in_days >= 7 && var.kms_key_deletion_window_in_days <= 30
    error_message = "kms_key_deletion_window_in_days must be between 7 and 30."
  }
}

variable "kms_data_key_reuse_period_seconds" {
  description = "How long SQS may reuse a KMS data key when customer-managed encryption is selected."
  type        = number
  default     = 300
  validation {
    condition     = var.kms_data_key_reuse_period_seconds >= 60 && var.kms_data_key_reuse_period_seconds <= 86400
    error_message = "kms_data_key_reuse_period_seconds must be between 60 and 86400."
  }
}

variable "sender_principal_arns" {
  description = "AWS principal ARNs allowed to send messages to the source queue."
  type        = list(string)
  default     = []
}

variable "additional_policy_statements" {
  description = "Additional resource-policy statements attached to the source queue. Resources are restricted to the source queue ARN."
  type = list(object({
    sid        = string
    effect     = optional(string, "Allow")
    actions    = list(string)
    principals = list(object({ type = string, identifiers = list(string) }))
    conditions = optional(list(object({ test = string, variable = string, values = list(string) })), [])
  }))
  default = []
  validation {
    condition = alltrue([for statement in var.additional_policy_statements :
      contains(["Allow", "Deny"], statement.effect) && length(statement.actions) > 0 && length(statement.principals) > 0
    ])
    error_message = "Each additional policy statement must use effect Allow or Deny and include actions and principals."
  }
}

variable "enable_alarms" {
  description = "Whether to create queue age and DLQ depth alarms."
  type        = bool
  default     = true
}

variable "alarm_actions" {
  description = "ARNs notified when an alarm enters ALARM."
  type        = list(string)
  default     = []
}

variable "ok_actions" {
  description = "ARNs notified when an alarm returns to OK."
  type        = list(string)
  default     = []
}

variable "alarm_evaluation_periods" {
  description = "Number of periods CloudWatch evaluates before changing alarm state."
  type        = number
  default     = 1
  validation {
    condition     = var.alarm_evaluation_periods >= 1
    error_message = "alarm_evaluation_periods must be at least 1."
  }
}

variable "alarm_period_seconds" {
  description = "Length of each CloudWatch alarm evaluation period."
  type        = number
  default     = 300
  validation {
    condition     = var.alarm_period_seconds >= 10
    error_message = "alarm_period_seconds must be at least 10."
  }
}

variable "dlq_depth_alarm_threshold" {
  description = "Visible messages in the DLQ that trigger an alarm."
  type        = number
  default     = 1
  validation {
    condition     = var.dlq_depth_alarm_threshold >= 0
    error_message = "dlq_depth_alarm_threshold must be zero or greater."
  }
}

variable "queue_age_alarm_threshold_seconds" {
  description = "Age of the oldest source message that triggers an alarm. Null disables this alarm."
  type        = number
  default     = 3600
  nullable    = true
  validation {
    condition     = var.queue_age_alarm_threshold_seconds == null || var.queue_age_alarm_threshold_seconds >= 0
    error_message = "queue_age_alarm_threshold_seconds must be null or zero or greater."
  }
}
