# AWS S3 module

Small wrapper around `cloudposse/s3-bucket/aws` version `4.12.0`.

The caller supplies the complete bucket name, Cloud Posse label context,
tags, and lifecycle rules. Naming conventions, workload IAM, Firehose,
Glue, and EventBridge remain caller responsibilities.

## Behavior

- Versioning enabled by default and configurable with `versioning_enabled`.
- Default encryption uses `AES256`, with `blocked_encryption_types = ["NONE"]`; callers may select `aws:kms` and supply a KMS key ARN.
- Bucket policy requires HTTPS by default.
- Bucket ownership defaults to `BucketOwnerEnforced`; object ACLs are disabled by default.
- All four public-access-block settings are enabled by default.
- `force_destroy = false` by default; callers may explicitly enable destructive deletion.
- No IAM user created.
- Context and explicit tags retain Cloud Posse's merging behavior.
  The wrapper adds no tags.

Lifecycle rules are enabled and match the supplied prefixes. Current-version
expiration, noncurrent-version expiration, and incomplete multipart-upload
cleanup are configured independently. An empty rules list creates no
lifecycle configuration.

## Usage

Consume this module through a Git subdirectory source pinned to a verified
release commit. Replace `VERIFIED_RELEASE_COMMIT_SHA` below with the full
commit SHA resolved from the actual release tag before use.

This example assumes the caller already defines its label module, environment,
account identity, and retention configuration.

```hcl
module "event_analytics_bucket" {
  source = "git::https://github.com/project-init/infrastructure.git//modules/aws/s3?ref=VERIFIED_RELEASE_COMMIT_SHA"

  name    = "${module.label_event_analytics_bucket.id}-${var.environment}-${data.aws_caller_identity.current.account_id}"
  context = module.label_event_analytics_bucket.context

  tags = {
    Purpose = "business-event-analytics"
  }

  lifecycle_rules = [
    {
      id                                     = "raw-retention"
      prefix                                 = "raw/"
      expiration_days                        = var.event_analytics.raw_retention_days
      noncurrent_expiration_days             = var.event_analytics.noncurrent_version_retention_days
      abort_incomplete_multipart_upload_days = var.event_analytics.abort_incomplete_multipart_upload_days
    },
    {
      id                                     = "failed-retention"
      prefix                                 = "failed/"
      expiration_days                        = var.event_analytics.failed_retention_days
      noncurrent_expiration_days             = var.event_analytics.noncurrent_version_retention_days
      abort_incomplete_multipart_upload_days = var.event_analytics.abort_incomplete_multipart_upload_days
    },
  ]
}
```

Data Platform should retain its existing prefix locals when migrating.
Its staging values are 14 days for raw expiration, 30 days for failed
expiration, and 7 days each for noncurrent expiration and multipart cleanup.

## Lifecycle rule fields

Each lifecycle rule requires:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `string` | Unique, nonblank rule ID, at most 255 characters. |
| `prefix` | `string` | Object key prefix; empty string matches all objects. |
| `expiration_days` | `number` | Positive integer days before current-object expiration. |
| `noncurrent_expiration_days` | `number` | Positive integer days before noncurrent-version expiration. |
| `abort_incomplete_multipart_upload_days` | `number` | Positive integer days before unfinished multipart uploads are aborted. |

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.3.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.22.0, < 7.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bucket"></a> [bucket](#module\_bucket) | cloudposse/s3-bucket/aws | 4.12.0 |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_allow_ssl_requests_only"></a> [allow\_ssl\_requests\_only](#input\_allow\_ssl\_requests\_only) | Whether the bucket policy denies requests that do not use HTTPS. | `bool` | `true` | no |
| <a name="input_block_public_acls"></a> [block\_public\_acls](#input\_block\_public\_acls) | Whether S3 blocks new public ACLs on the bucket. | `bool` | `true` | no |
| <a name="input_block_public_policy"></a> [block\_public\_policy](#input\_block\_public\_policy) | Whether S3 blocks new public bucket policies. | `bool` | `true` | no |
| <a name="input_blocked_encryption_types"></a> [blocked\_encryption\_types](#input\_blocked\_encryption\_types) | Encryption types blocked by the bucket encryption configuration. | `list(string)` | <pre>[<br/>  "NONE"<br/>]</pre> | no |
| <a name="input_context"></a> [context](#input\_context) | Cloud Posse label context passed through to the bucket module. | `any` | n/a | yes |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Whether Terraform may delete the bucket when it still contains objects. | `bool` | `false` | no |
| <a name="input_ignore_public_acls"></a> [ignore\_public\_acls](#input\_ignore\_public\_acls) | Whether S3 ignores public ACLs on the bucket. | `bool` | `true` | no |
| <a name="input_kms_master_key_arn"></a> [kms\_master\_key\_arn](#input\_kms\_master\_key\_arn) | KMS key ARN used when sse\_algorithm is aws:kms. An empty value uses the AWS-managed S3 key. | `string` | `""` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Enabled prefix-based lifecycle rules. Retention choices belong to the caller. | <pre>list(object({<br/>    id                                     = string<br/>    prefix                                 = string<br/>    expiration_days                        = number<br/>    noncurrent_expiration_days             = number<br/>    abort_incomplete_multipart_upload_days = number<br/>  }))</pre> | `[]` | no |
| <a name="input_name"></a> [name](#input\_name) | Complete bucket name supplied by the caller. | `string` | n/a | yes |
| <a name="input_restrict_public_buckets"></a> [restrict\_public\_buckets](#input\_restrict\_public\_buckets) | Whether S3 restricts public bucket policies. | `bool` | `true` | no |
| <a name="input_s3_object_ownership"></a> [s3\_object\_ownership](#input\_s3\_object\_ownership) | S3 object ownership mode for the bucket. | `string` | `"BucketOwnerEnforced"` | no |
| <a name="input_sse_algorithm"></a> [sse\_algorithm](#input\_sse\_algorithm) | Server-side encryption algorithm used by the bucket. | `string` | `"AES256"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags merged with the Cloud Posse label context. | `map(string)` | `{}` | no |
| <a name="input_versioning_enabled"></a> [versioning\_enabled](#input\_versioning\_enabled) | Whether S3 object versioning is enabled. | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bucket_arn"></a> [bucket\_arn](#output\_bucket\_arn) | Bucket ARN. |
| <a name="output_bucket_id"></a> [bucket\_id](#output\_bucket\_id) | Bucket name. |
| <a name="output_env_variables"></a> [env\_variables](#output\_env\_variables) | Environment variables containing S3\_BUCKET for the bucket. |
<!-- END_TF_DOCS -->

The caller supplies the AWS provider configuration. Cloud Posse also requires
the Time provider. The tracked lockfile records resolved provider versions
for this module's development and tests; consuming roots use their own lockfiles.

## Validation and tests

Run from the repository root using the mise-pinned OpenTofu 1.11.4:

```sh
mise run test:module modules/aws/s3
```

For separate formatting and validation checks:

```sh
mise exec -- tofu -chdir=modules/aws/s3 fmt -check -recursive
mise exec -- tofu -chdir=modules/aws/s3 validate
```

Tests use mock AWS and Time providers and make no AWS API calls.
They cover a valid lifecycle configuration, selected invalid inputs,
and output forwarding.

Use `test -verbose` to inspect planned resource settings and tag merging.
The IAM policy document data source is mocked, so these tests do not verify
the generated HTTPS policy JSON. They also do not verify live state or prove
that an existing bucket migration is free of changes.

## Migrating Data Platform

The wrapper's internal Cloud Posse module is named `bucket`. Keep this name
stable because it forms part of every managed resource address.

Data Platform currently calls Cloud Posse 4.12.0 directly through
`module.event_analytics_bucket`. Introducing this wrapper adds `module.bucket`
to the resource addresses even when the outer module name remains unchanged.

The following mapping is derived from configuration, not verified live state.
Before migrating, compare it with the staging state resource inventory.

Add these moved blocks in Data Platform's `terraform/modules/main` module,
alongside the `event_analytics_bucket` module call:

```hcl
moved {
  from = module.event_analytics_bucket.aws_s3_bucket.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_versioning.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_versioning.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_server_side_encryption_configuration.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_server_side_encryption_configuration.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_policy.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_policy.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_public_access_block.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_public_access_block.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_ownership_controls.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_ownership_controls.default[0]
}

moved {
  from = module.event_analytics_bucket.aws_s3_bucket_lifecycle_configuration.default[0]
  to   = module.event_analytics_bucket.module.bucket.aws_s3_bucket_lifecycle_configuration.default[0]
}

moved {
  from = module.event_analytics_bucket.time_sleep.wait_for_aws_s3_bucket_settings[0]
  to   = module.event_analytics_bucket.module.bucket.time_sleep.wait_for_aws_s3_bucket_settings[0]
}
```

These addresses are relative to Data Platform's `main` module. Its enclosing
module path is retained automatically. Keep the moved blocks so environments
that migrate later can follow the same address changes.

In the separate consuming PR:

1. Use the actual S3 release tag to resolve and verify its full commit SHA.
   Pin the Git subdirectory source to that SHA and remove the registry-only
   `version` argument from the old module call.
2. Preserve the existing bucket name expression, label context, tags, prefix
   locals, and retention values. Rename the caller argument `bucket_name`
   to `name` and translate lifecycle inputs to this wrapper's interface.
   Remove settings now fixed inside the wrapper.
3. Add the moved blocks after checking the staging resource inventory.
   Leave workload IAM, Firehose, Glue, and EventBridge configuration in place.
4. Initialize using the consuming root's provider lockfile. Confirm its AWS
   provider satisfies `>= 6.22.0, < 7.0.0`; review any required provider upgrade
   separately from the extraction.
5. Review the staging plan. All eight existing resources should map to their
   new addresses without recreation or unintended configuration changes.
   Confirm bucket outputs, tags, encryption, HTTPS policy, public-access
   controls, ownership, versioning, and lifecycle settings are preserved.

The mock module tests do not establish migration safety. The consuming
staging plan is the required verification before applying the migration.
