data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  merged_tags = merge(
    {
      ManagedBy = "tofu"
      Module    = "sqs"
    },
    var.tags,
  )

  queue_arn          = "arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${var.name}"
  created_dlq_arn    = "arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${var.name}-dlq"
  effective_dlq_arn  = var.enable_dlq ? local.created_dlq_arn : var.dlq_arn
  effective_dlq_name = local.effective_dlq_arn == null ? null : element(split(":", local.effective_dlq_arn), 5)
  effective_dlq_url  = local.effective_dlq_arn == null ? null : "https://sqs.${data.aws_region.current.region}.${data.aws_partition.current.dns_suffix}/${data.aws_caller_identity.current.account_id}/${local.effective_dlq_name}"

  create_kms_key = var.create_kms_key && var.kms_key_arn == null
  kms_key_arn = var.kms_key_arn != null ? var.kms_key_arn : (
    local.create_kms_key ? aws_kms_key.this[0].arn : null
  )

  kms_service_principals = distinct(flatten([
    for statement in var.additional_policy_statements : flatten([
      for principal in statement.principals : principal.identifiers
      if statement.effect == "Allow" &&
      principal.type == "Service" &&
      anytrue([for action in statement.actions : contains(["*", "sqs:*", "sqs:sendmessage"], lower(action))])
    ])
  ]))

  kms_sender_principal_arns = distinct(var.sender_principal_arns)

  create_queue_policy = length(var.sender_principal_arns) > 0 || length(var.additional_policy_statements) > 0
}

resource "terraform_data" "validate_configuration" {
  lifecycle {
    precondition {
      condition     = local.effective_dlq_arn == null || (var.max_receive_count >= 1 && var.max_receive_count <= 1000 && floor(var.max_receive_count) == var.max_receive_count)
      error_message = "max_receive_count must be an integer between 1 and 1000 when a DLQ is configured."
    }
    precondition {
      condition     = !var.enable_dlq || var.dlq_arn == null
      error_message = "dlq_arn must be null when enable_dlq is true."
    }
    precondition {
      condition = var.dlq_arn == null || can(regex(
        "^arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:[a-zA-Z0-9_-]{1,80}$", var.dlq_arn
      ))
      error_message = "dlq_arn must identify a standard queue in the same partition, region, and account."
    }
    precondition {
      condition     = !var.create_kms_key || var.kms_key_arn == null
      error_message = "kms_key_arn must be null when create_kms_key is true."
    }
    precondition {
      condition     = !var.enable_dlq || var.dlq_message_retention_seconds >= var.message_retention_seconds
      error_message = "dlq_message_retention_seconds must be at least message_retention_seconds."
    }
    precondition {
      condition     = !var.enable_dlq || length("${var.name}-dlq") <= 80
      error_message = "The generated DLQ name must be no longer than 80 characters."
    }
    precondition {
      condition     = length(var.additional_policy_statements) == length(distinct([for statement in var.additional_policy_statements : statement.sid]))
      error_message = "Additional queue policy statement SIDs must be unique."
    }

    precondition {
      condition     = length(var.sender_principal_arns) == 0 || !contains([for statement in var.additional_policy_statements : statement.sid], "AllowConfiguredSenders")
      error_message = "Additional queue policy statement SID AllowConfiguredSenders is reserved when sender_principal_arns is configured."
    }
  }
}

data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0
  statement {
    sid       = "EnableAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  dynamic "statement" {
    for_each = length(local.kms_service_principals) > 0 ? [1] : []

    content {
      sid       = "AllowConfiguredServices"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = local.kms_service_principals
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [data.aws_caller_identity.current.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = length(local.kms_sender_principal_arns) > 0 ? [1] : []

    content {
      sid       = "AllowConfiguredSenders"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = local.kms_sender_principal_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count                   = local.create_kms_key ? 1 : 0
  description             = "SQS encryption key for ${var.name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = local.merged_tags
}

resource "aws_kms_alias" "this" {
  count         = local.create_kms_key ? 1 : 0
  name          = "alias/${var.name}-sqs"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_sqs_queue" "dlq" {
  count                             = var.enable_dlq ? 1 : 0
  name                              = "${var.name}-dlq"
  message_retention_seconds         = var.dlq_message_retention_seconds
  sqs_managed_sse_enabled           = local.kms_key_arn == null ? true : null
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = local.kms_key_arn == null ? null : var.kms_data_key_reuse_period_seconds
  tags                              = merge(local.merged_tags, { QueueRole = "dead-letter" })
  depends_on                        = [terraform_data.validate_configuration]
}

resource "aws_sqs_queue" "this" {
  name                              = var.name
  delay_seconds                     = var.delay_seconds
  max_message_size                  = var.max_message_size_bytes
  message_retention_seconds         = var.message_retention_seconds
  receive_wait_time_seconds         = var.receive_wait_time_seconds
  visibility_timeout_seconds        = var.visibility_timeout_seconds
  sqs_managed_sse_enabled           = local.kms_key_arn == null ? true : null
  kms_master_key_id                 = local.kms_key_arn
  kms_data_key_reuse_period_seconds = local.kms_key_arn == null ? null : var.kms_data_key_reuse_period_seconds
  tags                              = merge(local.merged_tags, { QueueRole = "source" })
  depends_on                        = [terraform_data.validate_configuration]
}

resource "aws_sqs_queue_redrive_policy" "this" {
  count = local.effective_dlq_arn == null ? 0 : 1

  queue_url = aws_sqs_queue.this.url
  redrive_policy = jsonencode({
    deadLetterTargetArn = var.enable_dlq ? aws_sqs_queue.dlq[0].arn : var.dlq_arn
    maxReceiveCount     = var.max_receive_count
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  count = var.enable_dlq ? 1 : 0

  queue_url = aws_sqs_queue.dlq[0].url
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.this.arn]
  })
}

data "aws_iam_policy_document" "queue_policy" {
  count = local.create_queue_policy ? 1 : 0

  version = "2012-10-17"
  dynamic "statement" {
    for_each = length(var.sender_principal_arns) > 0 ? [1] : []
    content {
      sid       = "AllowConfiguredSenders"
      effect    = "Allow"
      actions   = ["sqs:SendMessage"]
      resources = [local.queue_arn]
      principals {
        type        = "AWS"
        identifiers = var.sender_principal_arns
      }
    }
  }
  dynamic "statement" {
    for_each = { for item in var.additional_policy_statements : item.sid => item }
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = [local.queue_arn]
      dynamic "principals" {
        for_each = statement.value.principals
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }
      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}
resource "aws_sqs_queue_policy" "this" {
  count     = local.create_queue_policy ? 1 : 0
  queue_url = aws_sqs_queue.this.url
  policy    = data.aws_iam_policy_document.queue_policy[0].json
}

resource "aws_cloudwatch_metric_alarm" "dlq_depth" {
  count               = var.enable_alarms && local.effective_dlq_arn != null ? 1 : 0
  alarm_name          = "${var.name}-dlq-depth"
  alarm_description   = "SQS dead-letter queue ${local.effective_dlq_name} contains messages"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.dlq_depth_alarm_threshold
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  dimensions          = { QueueName = local.effective_dlq_name }
  tags                = local.merged_tags
}
resource "aws_cloudwatch_metric_alarm" "queue_age" {
  count               = var.enable_alarms && var.queue_age_alarm_threshold_seconds != null ? 1 : 0
  alarm_name          = "${var.name}-oldest-message-age"
  alarm_description   = "SQS queue ${var.name} has an old unprocessed message"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = var.queue_age_alarm_threshold_seconds
  evaluation_periods  = var.alarm_evaluation_periods
  period              = var.alarm_period_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions
  ok_actions          = var.ok_actions
  dimensions          = { QueueName = aws_sqs_queue.this.name }
  tags                = local.merged_tags
}

data "aws_iam_policy_document" "sender" {
  statement {
    sid       = "SendMessages"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [local.queue_arn]
  }

  dynamic "statement" {
    for_each = local.kms_key_arn == null ? [] : [local.kms_key_arn]

    content {
      sid       = "EncryptMessages"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "receiver" {
  statement {
    sid       = "ReceiveMessages"
    effect    = "Allow"
    actions   = ["sqs:ChangeMessageVisibility", "sqs:DeleteMessage", "sqs:GetQueueAttributes", "sqs:ReceiveMessage"]
    resources = [local.queue_arn]
  }

  dynamic "statement" {
    for_each = local.kms_key_arn == null ? [] : [local.kms_key_arn]

    content {
      sid       = "DecryptMessages"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}
