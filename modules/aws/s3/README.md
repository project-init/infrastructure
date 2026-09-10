# AWS S3 module

Small wrapper around `cloudposse/s3-bucket/aws` version `4.12.0`.

The caller supplies the complete bucket name, Cloud Posse label context,
tags, and lifecycle rules. Naming conventions, workload IAM, Firehose,
Glue, and EventBridge remain caller responsibilities.

## Behavior

- Versioning enabled.
- Default encryption uses `AES256`, with `blocked_encryption_types = ["NONE"]`.
- Bucket policy requires HTTPS.
- Bucket ownership is `BucketOwnerEnforced`; object ACLs are disabled.
- All four public-access-block settings enabled.
- `force_destroy = false`: deletion does not automatically empty the bucket.
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

## Inputs

| Name | Type | Default | Description |
| --- | --- | --- | --- |
| `name` | `string` | Required | Complete bucket name; must satisfy AWS bucket naming rules. |
| `context` | `any` | Required | Complete Cloud Posse label context, normally a label module's `context` output. An empty object is not supported. |
| `tags` | `map(string)` | `{}` | Additional tags merged by Cloud Posse. |
| `lifecycle_rules` | `list(object)` | `[]` | Enabled prefix-based lifecycle rules. |

Each lifecycle rule requires:

| Field | Type | Description |
| --- | --- | --- |
| `id` | `string` | Unique, nonblank rule ID, at most 255 characters. |
| `prefix` | `string` | Object key prefix; empty string matches all objects. |
| `expiration_days` | `number` | Positive integer days before current-object expiration. |
| `noncurrent_expiration_days` | `number` | Positive integer days before noncurrent-version expiration. |
| `abort_incomplete_multipart_upload_days` | `number` | Positive integer days before unfinished multipart uploads are aborted. |

## Outputs

| Name | Description |
| --- | --- |
| `bucket_id` | Bucket name. |
| `bucket_arn` | Bucket ARN. |

## Requirements

| Dependency | Version |
| --- | --- |
| Terraform/OpenTofu | `>= 1.3.0` |
| AWS provider | `>= 6.22.0, < 7.0.0` |
| Cloud Posse S3 module | `4.12.0` |

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
