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
