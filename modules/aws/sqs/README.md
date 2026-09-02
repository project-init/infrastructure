# SQS Queue Module

Creates an encrypted standard Amazon SQS queue with an optional module-managed or existing dead-letter queue (DLQ), configurable access policy, and CloudWatch alarms.

The module exposes queue identifiers and IAM policy documents so deployment code can connect producers and consumers without recreating SQS configuration.

## Usage

```hcl
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
      values   = [module.business_events_bus.rule_arns["database"]]
    }]
  }]

  alarm_actions = [module.platform_alerts.sns_topic_arn]
  ok_actions    = [module.platform_alerts.sns_topic_arn]

  tags = {
    Team    = "DataPlatform"
    Project = "events-api"
  }
}
```

## Behavior

This module creates standard queues. FIFO queues are currently out of scope.

By default, the module creates `${name}-dlq`, retains source messages for four days and DLQ messages for fourteen days, and moves a message to the DLQ after five receives. Set `enable_dlq = false` to omit redrive. To use an existing standard queue, set `enable_dlq = false` and supply `dlq_arn`.

An existing DLQ must be in the same AWS partition, account, and Region as the source queue. A module-created DLQ must retain messages for at least as long as the source queue and uses a `byQueue` redrive-allow policy restricted to its paired source queue.

## Gommon configuration mapping

The `queue_url` output maps to Gommon's `configs.SQS.QueueURL` field. For applications that nest `configs.SQS` under the `SQS` environment prefix, inject the output as `SQS_QUEUE_URL`:

```hcl
environment_variables = {
  SQS_QUEUE_URL = module.database_events_queue.queue_url
}
```

The other primary integration outputs have infrastructure-specific consumers:

- Use `queue_arn` as the EventBridge target ARN.
- Attach `receiver_policy_json` to the worker's IAM role.

The deployment layer owns these mappings; the module does not create an ECS task or depend on Gommon.

## Encryption

All module-created queues are encrypted at rest. By default, the module creates a dedicated rotating customer-managed KMS key and `alias/${name}-sqs`. Set `create_kms_key = false` to use SQS-managed encryption. To use an existing customer-managed key, set `create_kms_key = false` and provide `kms_key_arn`.

When customer-managed encryption is selected, `sender_policy_json` includes `kms:Decrypt` and `kms:GenerateDataKey`, while `receiver_policy_json` includes `kms:Decrypt`. The caller must attach those identity policies to the applicable roles. For a module-created key, configured sender ARNs and service principals allowed to send through `additional_policy_statements` are also authorized in its key policy. Service access is restricted by `aws:SourceAccount`, allowing integrations such as EventBridge to use the encrypted queue without trusting other accounts.

When using `kms_key_arn`, the caller remains responsible for an existing key policy that permits the producer and consumer identities or AWS services.

## Access policy

No SQS resource policy is attached by default. `sender_principal_arns` grants selected AWS principals `sqs:SendMessage`. `additional_policy_statements` supports AWS or service principals and optional IAM conditions.

Every additional statement's `Resource` is fixed to the source queue ARN. `sender_policy_json` and `receiver_policy_json` are identity policies for caller-managed roles; this module does not create those roles.

## Observability

The module can alarm on visible DLQ messages and the age of the oldest source message. Notification actions, thresholds, periods, and evaluation periods are configurable. Set `queue_age_alarm_threshold_seconds = null` to disable only the age alarm, or `enable_alarms = false` to disable both.

SQS has no native message-to-CloudWatch-Logs delivery. Account-wide CloudTrail data events and application processing logs remain caller responsibilities.

## Inputs

| Name                                | Type           |   Default | Required | Description                                       |
| ----------------------------------- | -------------- | --------: | :------: | ------------------------------------------------- |
| `name`                              | `string`       |         — |   Yes    | Standard queue name and resource prefix.          |
| `tags`                              | `map(string)`  |      `{}` |    No    | Additional tags; caller values take precedence.   |
| `message_retention_seconds`         | `number`       |  `345600` |    No    | Source retention, 60–1,209,600 seconds.           |
| `visibility_timeout_seconds`        | `number`       |      `30` |    No    | Visibility timeout, 0–43,200 seconds.             |
| `max_message_size_bytes`            | `number`       |  `262144` |    No    | Maximum message size, 1,024–262,144 bytes.        |
| `delay_seconds`                     | `number`       |       `0` |    No    | Default delivery delay, 0–900 seconds.            |
| `receive_wait_time_seconds`         | `number`       |       `0` |    No    | Long-polling wait, 0–20 seconds.                  |
| `enable_dlq`                        | `bool`         |    `true` |    No    | Create and attach a module-managed DLQ.           |
| `max_receive_count`                 | `number`       |       `5` |    No    | Receives before redrive when a DLQ is configured. |
| `dlq_message_retention_seconds`     | `number`       | `1209600` |    No    | Module-created DLQ retention.                     |
| `dlq_arn`                           | `string`       |    `null` |    No    | Existing DLQ ARN used when `enable_dlq = false`.  |
| `kms_key_arn`                       | `string`       |    `null` |    No    | Existing customer-managed KMS key ARN.            |
| `create_kms_key`                    | `bool`         |    `true` |    No    | Create a dedicated customer-managed key.          |
| `kms_key_deletion_window_in_days`   | `number`       |      `30` |    No    | Created key deletion window, 7–30 days.           |
| `kms_data_key_reuse_period_seconds` | `number`       |     `300` |    No    | KMS data-key reuse period, 60–86,400 seconds.     |
| `sender_principal_arns`             | `list(string)` |      `[]` |    No    | AWS principals allowed to send messages.          |
| `additional_policy_statements`      | `list(object)` |      `[]` |    No    | Additional source queue policy statements.        |
| `enable_alarms`                     | `bool`         |    `true` |    No    | Enable queue-age and DLQ-depth alarms.            |
| `alarm_actions`                     | `list(string)` |      `[]` |    No    | ARNs notified on ALARM.                           |
| `ok_actions`                        | `list(string)` |      `[]` |    No    | ARNs notified on recovery.                        |
| `alarm_evaluation_periods`          | `number`       |       `1` |    No    | Alarm evaluation periods.                         |
| `alarm_period_seconds`              | `number`       |     `300` |    No    | Alarm period in seconds.                          |
| `dlq_depth_alarm_threshold`         | `number`       |       `1` |    No    | Visible DLQ messages that trigger an alarm.       |
| `queue_age_alarm_threshold_seconds` | `number`       |    `3600` |    No    | Oldest source-message age; null disables it.      |

## Outputs

| Name                                     | Description                                         |
| ---------------------------------------- | --------------------------------------------------- |
| `queue_arn` / `queue_url` / `queue_name` | Source queue identifiers.                           |
| `dlq_arn` / `dlq_url` / `dlq_name`       | Configured DLQ identifiers, or null.                |
| `kms_key_arn`                            | Customer-managed key ARN, or null for SSE-SQS.      |
| `alarm_arns`                             | Created alarm ARNs keyed by alarm type.             |
| `sender_policy_json`                     | IAM policy for sending and, when needed, KMS use.   |
| `receiver_policy_json`                   | IAM policy for consuming and, when needed, KMS use. |

## Requirements

| Name               | Version    |
| ------------------ | ---------- |
| OpenTofu/Terraform | `>= 1.3.0` |
| AWS provider       | `~> 6.0`   |

The caller supplies the AWS provider configuration. The module contains no provider block.

## Resources not created

The module does not create CloudTrail configuration, application log delivery, producer or consumer roles, runtime consumers, EventBridge rules or targets, environment instances, or cross-account DLQ sharing.

## Validation and tests

```shell
tofu -chdir=modules/aws/sqs init -backend=false
tofu -chdir=modules/aws/sqs fmt -check -recursive
tofu -chdir=modules/aws/sqs validate
tofu -chdir=modules/aws/sqs test
```

Plan tests use the AWS mock provider and create no AWS resources.
