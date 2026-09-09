output "queue_arn" {
  description = "ARN of the source queue."
  value       = aws_sqs_queue.this.arn
}
output "queue_url" {
  description = "URL of the source queue."
  value       = aws_sqs_queue.this.url
}
output "queue_name" {
  description = "Name of the source queue."
  value       = aws_sqs_queue.this.name
}
output "dlq_arn" {
  description = "ARN of the configured DLQ, or null."
  value       = var.enable_dlq ? try(aws_sqs_queue.dlq[0].arn, null) : var.dlq_arn
}
output "dlq_url" {
  description = "URL of the configured DLQ, or null."
  value       = var.enable_dlq ? try(aws_sqs_queue.dlq[0].url, null) : local.effective_dlq_url
}
output "dlq_name" {
  description = "Name of the configured DLQ, or null."
  value       = local.effective_dlq_name
}
output "kms_key_arn" {
  description = "Customer-managed KMS key ARN, or null for SSE-SQS."
  value       = local.kms_key_arn
}
output "alarm_arns" {
  description = "Map of created CloudWatch alarm ARNs."
  value = merge(
    { for index, alarm in aws_cloudwatch_metric_alarm.dlq_depth : "dlq_depth.${index}" => alarm.arn },
    { for index, alarm in aws_cloudwatch_metric_alarm.queue_age : "queue_age.${index}" => alarm.arn },
  )
}
output "sender_policy_json" {
  description = "IAM policy JSON granting SendMessage and required customer-managed KMS key use."
  value       = data.aws_iam_policy_document.sender.json
}
output "receiver_policy_json" {
  description = "IAM policy JSON granting message-consumer and required customer-managed KMS key permissions."
  value       = data.aws_iam_policy_document.receiver.json
}

output "env_variables" {
  description = "Environment variables containing SQS_QUEUE_URL for the source queue."
  value = [
    {
      name  = "SQS_QUEUE_URL"
      value = aws_sqs_queue.this.url
    }
  ]
}
