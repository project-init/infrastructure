mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012", arn = "arn:aws:iam::123456789012:user/test", user_id = "AIDATEST" } }
  mock_data "aws_partition" { defaults = { partition = "aws", dns_suffix = "amazonaws.com" } }
  mock_data "aws_region" { defaults = { name = "us-east-1", region = "us-east-1" } }
  mock_data "aws_iam_policy_document" { defaults = { json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}" } }
  mock_resource "aws_sqs_queue" { defaults = { arn = "arn:aws:sqs:us-east-1:123456789012:mock", url = "https://sqs.us-east-1.amazonaws.com/123456789012/mock" } }
  mock_resource "aws_kms_key" { defaults = { arn = "arn:aws:kms:us-east-1:123456789012:key/mock", key_id = "mock" } }
  mock_resource "aws_cloudwatch_metric_alarm" { defaults = { arn = "arn:aws:cloudwatch:us-east-1:123456789012:alarm:mock" } }
}

run "defaults" {
  command = plan
  variables { name = "business-events" }
  assert {
    condition     = aws_sqs_queue.this.name == "business-events" && aws_sqs_queue.this.kms_master_key_id == aws_kms_key.this[0].arn
    error_message = "The source queue must use the requested name and module-created KMS key."
  }
  assert {
    condition     = length(aws_sqs_queue.dlq) == 1 && aws_sqs_queue.dlq[0].name == "business-events-dlq" && aws_sqs_queue.dlq[0].kms_master_key_id == aws_kms_key.this[0].arn
    error_message = "Defaults must create a DLQ encrypted with the module-created KMS key."
  }
  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).deadLetterTargetArn == aws_sqs_queue.dlq[0].arn && jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).maxReceiveCount == 5
    error_message = "The source queue must redrive to the generated DLQ after five receives."
  }
  assert {
    condition     = jsondecode(aws_sqs_queue_redrive_allow_policy.dlq[0].redrive_allow_policy).redrivePermission == "byQueue" && jsondecode(aws_sqs_queue_redrive_allow_policy.dlq[0].redrive_allow_policy).sourceQueueArns[0] == aws_sqs_queue.this.arn
    error_message = "The generated DLQ must accept only its paired source queue."
  }
  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation && length(aws_sqs_queue_policy.this) == 0 && length(output.alarm_arns) == 2
    error_message = "Defaults must create a rotating KMS key and two alarms without creating a queue policy."
  }
  assert {
    condition     = output.queue_url == aws_sqs_queue.this.url && output.queue_arn == aws_sqs_queue.this.arn && output.receiver_policy_json == data.aws_iam_policy_document.receiver.json
    error_message = "The module must expose the source queue URL, source queue ARN, and receiver policy."
  }
  assert {
    condition = (
      length(output.env_variables) == 1
      && output.env_variables[0].name == "SQS_QUEUE_URL"
      && output.env_variables[0].value == aws_sqs_queue.this.url
    )
    error_message = "This module must expose the queue URL as SQS_QUEUE_URL"
  }
}

run "dlq_disabled" {
  command = plan
  variables {
    name       = "business-events"
    enable_dlq = false
  }
  assert {
    condition     = length(aws_sqs_queue.dlq) == 0 && length(aws_sqs_queue_redrive_policy.this) == 0 && length(aws_sqs_queue_redrive_allow_policy.dlq) == 0 && length(aws_cloudwatch_metric_alarm.dlq_depth) == 0
    error_message = "Disabling the DLQ must omit its queue, redrive decision, and alarm."
  }
}

run "bring_your_own_dlq" {
  command = plan
  variables {
    name       = "business-events"
    enable_dlq = false
    dlq_arn    = "arn:aws:sqs:us-east-1:123456789012:shared-dlq"
  }
  assert {
    condition     = length(aws_sqs_queue.dlq) == 0 && length(aws_sqs_queue_redrive_allow_policy.dlq) == 0 && jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).deadLetterTargetArn == "arn:aws:sqs:us-east-1:123456789012:shared-dlq" && output.dlq_name == "shared-dlq"
    error_message = "An existing DLQ must be attached and exposed without creating one."
  }
}

run "custom_queue_behavior" {
  command = plan
  variables {
    name                          = "worker-jobs"
    message_retention_seconds     = 86400
    dlq_message_retention_seconds = 604800
    visibility_timeout_seconds    = 120
    max_message_size_bytes        = 131072
    delay_seconds                 = 10
    receive_wait_time_seconds     = 20
    max_receive_count             = 8
  }
  assert {
    condition     = aws_sqs_queue.this.message_retention_seconds == 86400 && aws_sqs_queue.this.visibility_timeout_seconds == 120 && aws_sqs_queue.this.max_message_size == 131072 && jsondecode(aws_sqs_queue_redrive_policy.this[0].redrive_policy).maxReceiveCount == 8
    error_message = "Queue and redrive behavior overrides must be applied."
  }
}

run "bring_your_own_kms_key" {
  command = plan
  variables {
    name           = "business-events"
    create_kms_key = false
    kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/existing"
  }
  assert {
    condition     = length(aws_kms_key.this) == 0 && aws_sqs_queue.this.kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/existing" && aws_sqs_queue.dlq[0].kms_master_key_id == "arn:aws:kms:us-east-1:123456789012:key/existing"
    error_message = "An existing CMK must encrypt both queues."
  }
  assert {
    condition     = local.kms_key_arn == "arn:aws:kms:us-east-1:123456789012:key/existing"
    error_message = "Generated identity policies must select the configured customer-managed key."
  }
}

run "create_kms_key" {
  command = plan
  variables {
    name                  = "business-events"
    create_kms_key        = true
    sender_principal_arns = ["arn:aws:iam::123456789012:role/publisher"]
  }
  assert {
    condition     = length(aws_kms_key.this) == 1 && aws_kms_key.this[0].enable_key_rotation && aws_kms_alias.this[0].name == "alias/business-events-sqs"
    error_message = "Requested CMK creation must create a rotating key and alias."
  }
  assert {
    condition     = length(local.kms_sender_principal_arns) == 1 && contains(local.kms_sender_principal_arns, "arn:aws:iam::123456789012:role/publisher")
    error_message = "A module-created key policy must authorize configured sender principals."
  }
}

run "access_policy" {
  command = plan
  variables {
    name                  = "business-events"
    create_kms_key        = true
    sender_principal_arns = ["arn:aws:iam::123456789012:role/publisher"]
    additional_policy_statements = [{
      sid        = "AllowEventBridge"
      actions    = ["sqs:SendMessage"]
      principals = [{ type = "Service", identifiers = ["events.amazonaws.com"] }]
      conditions = [{ test = "ArnEquals", variable = "aws:SourceArn", values = ["arn:aws:events:us-east-1:123456789012:rule/events"] }]
    }]
  }
  assert {
    condition     = length(data.aws_iam_policy_document.queue_policy) == 1 && length(aws_sqs_queue_policy.this) == 1
    error_message = "Configured access statements must attach a queue policy."
  }
  assert {
    condition     = length(local.kms_service_principals) == 1 && contains(local.kms_service_principals, "events.amazonaws.com")
    error_message = "Allowed service principals must be propagated to the module-created KMS key policy."
  }
}

run "alarms" {
  command = plan
  variables {
    name                              = "business-events"
    dlq_depth_alarm_threshold         = 4
    queue_age_alarm_threshold_seconds = 900
    alarm_evaluation_periods          = 2
    alarm_period_seconds              = 60
  }
  assert {
    condition     = aws_cloudwatch_metric_alarm.dlq_depth[0].threshold == 4 && aws_cloudwatch_metric_alarm.queue_age[0].threshold == 900 && aws_cloudwatch_metric_alarm.queue_age[0].period == 60
    error_message = "Alarm settings must be configurable."
  }
}

run "alarms_disabled" {
  command = plan
  variables {
    name          = "business-events"
    enable_alarms = false
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.dlq_depth) == 0 && length(aws_cloudwatch_metric_alarm.queue_age) == 0
    error_message = "Alarms must be disableable."
  }
}

run "queue_age_alarm_disabled" {
  command = plan
  variables {
    name                              = "business-events"
    queue_age_alarm_threshold_seconds = null
  }
  assert {
    condition     = length(aws_cloudwatch_metric_alarm.queue_age) == 0 && length(aws_cloudwatch_metric_alarm.dlq_depth) == 1
    error_message = "The queue-age alarm must be independently disableable."
  }
}

run "validation_receive_count" {
  command = plan
  variables {
    name              = "events"
    max_receive_count = 0
  }
  expect_failures = [terraform_data.validate_configuration]
}
run "validation_conflicting_dlq" {
  command = plan
  variables {
    name    = "events"
    dlq_arn = "arn:aws:sqs:us-east-1:123456789012:dlq"
  }
  expect_failures = [terraform_data.validate_configuration]
}
run "validation_cross_account_dlq" {
  command = plan
  variables {
    name       = "events"
    enable_dlq = false
    dlq_arn    = "arn:aws:sqs:us-east-1:999999999999:dlq"
  }
  expect_failures = [terraform_data.validate_configuration]
}
run "validation_conflicting_kms" {
  command = plan
  variables {
    name           = "events"
    create_kms_key = true
    kms_key_arn    = "arn:aws:kms:us-east-1:123456789012:key/existing"
  }
  expect_failures = [terraform_data.validate_configuration]
}
run "validation_message_retention" {
  command = plan
  variables {
    name                      = "events"
    message_retention_seconds = 59
  }
  expect_failures = [var.message_retention_seconds]
}
run "validation_visibility_timeout" {
  command = plan
  variables {
    name                       = "events"
    visibility_timeout_seconds = 43201
  }
  expect_failures = [var.visibility_timeout_seconds]
}
run "validation_dlq_retention" {
  command = plan
  variables {
    name                          = "events"
    message_retention_seconds     = 604800
    dlq_message_retention_seconds = 86400
  }
  expect_failures = [terraform_data.validate_configuration]
}
run "validation_name" {
  command = plan
  variables { name = "invalid.queue" }
  expect_failures = [var.name]
}

run "validation_reserved_policy_sid" {
  command = plan
  variables {
    name                  = "events"
    sender_principal_arns = ["arn:aws:iam::123456789012:role/publisher"]
    additional_policy_statements = [{
      sid        = "AllowConfiguredSenders"
      actions    = ["sqs:SendMessage"]
      principals = [{ type = "Service", identifiers = ["events.amazonaws.com"] }]
    }]
  }
  expect_failures = [terraform_data.validate_configuration]
}
