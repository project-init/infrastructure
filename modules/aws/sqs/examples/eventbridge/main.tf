variable "eventbridge_rule_arn" {
  description = "ARN of the existing EventBridge rule allowed to send messages."
  type        = string
}

variable "alarm_topic_arn" {
  description = "ARN of the existing SNS topic used for alarm notifications."
  type        = string
}

module "database_events_queue" {
  source  = "project-init/sqs/aws"
  version = "0.1.0"

  name                       = "database-events"
  visibility_timeout_seconds = 120
  max_receive_count          = 5

  additional_policy_statements = [{
    sid     = "AllowEventBridge"
    actions = ["sqs:SendMessage"]
    principals = [{
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }]
    conditions = [{
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [var.eventbridge_rule_arn]
    }]
  }]

  alarm_actions = [var.alarm_topic_arn]
  ok_actions    = [var.alarm_topic_arn]

  tags = {
    Team    = "DataPlatform"
    Project = "events-api"
  }
}
