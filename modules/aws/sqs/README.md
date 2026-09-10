# SQS Queue Module

Creates an encrypted standard Amazon SQS queue with an optional module-managed or existing dead-letter queue (DLQ), configurable access policy, and CloudWatch alarms.

The module exposes queue identifiers and IAM policy documents so deployment code can connect producers and consumers without recreating SQS configuration.

## Usage

See the [EventBridge example](examples/eventbridge/main.tf) for module usage.

The example requires an existing EventBridge rule ARN and SNS alarm topic ARN.
Configure the AWS provider for your target account and Region before running it.
The deployment layer must also configure the EventBridge target to send events to the queue.

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

The `env_variables` output provides the same mapping as a ready-to-inject list of `name` and `value` objects.

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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.58.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudwatch_metric_alarm.dlq_depth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.queue_age](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_kms_alias.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_sqs_queue.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_sqs_queue_redrive_allow_policy.dlq](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_allow_policy) | resource |
| [aws_sqs_queue_redrive_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_redrive_policy) | resource |
| [terraform_data.validate_configuration](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.kms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.queue_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.receiver](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.sender](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_partition.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/partition) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_additional_policy_statements"></a> [additional\_policy\_statements](#input\_additional\_policy\_statements) | Additional resource-policy statements attached to the source queue. Resources are restricted to the source queue ARN. | <pre>list(object({<br/>    sid        = string<br/>    effect     = optional(string, "Allow")<br/>    actions    = list(string)<br/>    principals = list(object({ type = string, identifiers = list(string) }))<br/>    conditions = optional(list(object({ test = string, variable = string, values = list(string) })), [])<br/>  }))</pre> | `[]` | no |
| <a name="input_alarm_actions"></a> [alarm\_actions](#input\_alarm\_actions) | ARNs notified when an alarm enters ALARM. | `list(string)` | `[]` | no |
| <a name="input_alarm_evaluation_periods"></a> [alarm\_evaluation\_periods](#input\_alarm\_evaluation\_periods) | Number of periods CloudWatch evaluates before changing alarm state. | `number` | `1` | no |
| <a name="input_alarm_period_seconds"></a> [alarm\_period\_seconds](#input\_alarm\_period\_seconds) | Length of each CloudWatch alarm evaluation period. | `number` | `300` | no |
| <a name="input_create_kms_key"></a> [create\_kms\_key](#input\_create\_kms\_key) | Whether to create a dedicated customer-managed KMS key when kms\_key\_arn is null. | `bool` | `true` | no |
| <a name="input_delay_seconds"></a> [delay\_seconds](#input\_delay\_seconds) | Default delivery delay for messages. | `number` | `0` | no |
| <a name="input_dlq_arn"></a> [dlq\_arn](#input\_dlq\_arn) | ARN of an existing standard SQS queue to use as the DLQ when enable\_dlq is false. | `string` | `null` | no |
| <a name="input_dlq_depth_alarm_threshold"></a> [dlq\_depth\_alarm\_threshold](#input\_dlq\_depth\_alarm\_threshold) | Visible messages in the DLQ that trigger an alarm. | `number` | `1` | no |
| <a name="input_dlq_message_retention_seconds"></a> [dlq\_message\_retention\_seconds](#input\_dlq\_message\_retention\_seconds) | How long the module-created dead-letter queue retains messages. | `number` | `1209600` | no |
| <a name="input_enable_alarms"></a> [enable\_alarms](#input\_enable\_alarms) | Whether to create queue age and DLQ depth alarms. | `bool` | `true` | no |
| <a name="input_enable_dlq"></a> [enable\_dlq](#input\_enable\_dlq) | Whether the module creates and attaches a dead-letter queue. | `bool` | `true` | no |
| <a name="input_kms_data_key_reuse_period_seconds"></a> [kms\_data\_key\_reuse\_period\_seconds](#input\_kms\_data\_key\_reuse\_period\_seconds) | How long SQS may reuse a KMS data key when customer-managed encryption is selected. | `number` | `300` | no |
| <a name="input_kms_key_arn"></a> [kms\_key\_arn](#input\_kms\_key\_arn) | ARN of an existing customer-managed KMS key used by the source queue and module-created DLQ. | `string` | `null` | no |
| <a name="input_kms_key_deletion_window_in_days"></a> [kms\_key\_deletion\_window\_in\_days](#input\_kms\_key\_deletion\_window\_in\_days) | Deletion window for the module-created KMS key. | `number` | `30` | no |
| <a name="input_max_message_size_bytes"></a> [max\_message\_size\_bytes](#input\_max\_message\_size\_bytes) | Maximum message body size in bytes. | `number` | `262144` | no |
| <a name="input_max_receive_count"></a> [max\_receive\_count](#input\_max\_receive\_count) | Number of receives before SQS moves a message to the configured DLQ. | `number` | `5` | no |
| <a name="input_message_retention_seconds"></a> [message\_retention\_seconds](#input\_message\_retention\_seconds) | How long the source queue retains messages. | `number` | `345600` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the standard SQS queue and prefix for related resources. | `string` | n/a | yes |
| <a name="input_ok_actions"></a> [ok\_actions](#input\_ok\_actions) | ARNs notified when an alarm returns to OK. | `list(string)` | `[]` | no |
| <a name="input_queue_age_alarm_threshold_seconds"></a> [queue\_age\_alarm\_threshold\_seconds](#input\_queue\_age\_alarm\_threshold\_seconds) | Age of the oldest source message that triggers an alarm. Null disables this alarm. | `number` | `3600` | no |
| <a name="input_receive_wait_time_seconds"></a> [receive\_wait\_time\_seconds](#input\_receive\_wait\_time\_seconds) | Long-polling wait time for ReceiveMessage calls. | `number` | `0` | no |
| <a name="input_sender_principal_arns"></a> [sender\_principal\_arns](#input\_sender\_principal\_arns) | AWS principal ARNs allowed to send messages to the source queue. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags applied to taggable resources. Caller values take precedence. | `map(string)` | `{}` | no |
| <a name="input_visibility_timeout_seconds"></a> [visibility\_timeout\_seconds](#input\_visibility\_timeout\_seconds) | How long a received message remains hidden from other consumers. | `number` | `30` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_alarm_arns"></a> [alarm\_arns](#output\_alarm\_arns) | Map of created CloudWatch alarm ARNs. |
| <a name="output_dlq_arn"></a> [dlq\_arn](#output\_dlq\_arn) | ARN of the configured DLQ, or null. |
| <a name="output_dlq_name"></a> [dlq\_name](#output\_dlq\_name) | Name of the configured DLQ, or null. |
| <a name="output_dlq_url"></a> [dlq\_url](#output\_dlq\_url) | URL of the configured DLQ, or null. |
| <a name="output_env_variables"></a> [env\_variables](#output\_env\_variables) | Environment variables containing SQS\_QUEUE\_URL for the source queue. |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | Customer-managed KMS key ARN, or null for SSE-SQS. |
| <a name="output_queue_arn"></a> [queue\_arn](#output\_queue\_arn) | ARN of the source queue. |
| <a name="output_queue_name"></a> [queue\_name](#output\_queue\_name) | Name of the source queue. |
| <a name="output_queue_url"></a> [queue\_url](#output\_queue\_url) | URL of the source queue. |
| <a name="output_receiver_policy_json"></a> [receiver\_policy\_json](#output\_receiver\_policy\_json) | IAM policy JSON granting message-consumer and required customer-managed KMS key permissions. |
| <a name="output_sender_policy_json"></a> [sender\_policy\_json](#output\_sender\_policy\_json) | IAM policy JSON granting SendMessage and required customer-managed KMS key use. |
<!-- END_TF_DOCS -->

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
