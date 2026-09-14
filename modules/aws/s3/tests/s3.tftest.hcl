mock_provider "aws" {
  mock_data "aws_partition" {
    defaults = {
      partition  = "aws"
      dns_suffix = "amazonaws.com"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

mock_provider "time" {}

variables {
  name = "event-analytics-test-123456789012"

  context = {
    enabled     = true
    namespace   = null
    tenant      = null
    environment = null
    stage       = null
    name        = null
    delimiter   = null
    attributes  = []
    tags = {
      Team = "data-platform"
    }
    additional_tag_map  = {}
    regex_replace_chars = null
    label_order         = []
    id_length_limit     = null
    label_key_case      = null
    label_value_case    = null
    descriptor_formats  = {}
    labels_as_tags      = ["unset"]
  }
}

run "valid_configuration" {
  command = plan

  variables {
    tags = {
      Purpose = "business-event-analytics"
    }
    lifecycle_rules = [
      {
        id                                     = "raw-retention"
        prefix                                 = "raw/"
        expiration_days                        = 14
        noncurrent_expiration_days             = 7
        abort_incomplete_multipart_upload_days = 7
      },
      {
        id                                     = "failed-retention"
        prefix                                 = "failed/"
        expiration_days                        = 30
        noncurrent_expiration_days             = 7
        abort_incomplete_multipart_upload_days = 7
      },
    ]
  }
}

run "configurable_bucket_behavior" {
  command = plan

  variables {
    force_destroy            = true
    versioning_enabled       = false
    sse_algorithm            = "aws:kms"
    kms_master_key_arn       = "arn:aws:kms:us-east-1:123456789012:key/example"
    blocked_encryption_types = ["NONE"]
    allow_ssl_requests_only  = false
    s3_object_ownership      = "BucketOwnerPreferred"
    block_public_acls        = false
    block_public_policy      = false
    ignore_public_acls       = false
    restrict_public_buckets  = false
  }
}

run "reject_invalid_encryption_algorithm" {
  command = plan

  variables {
    sse_algorithm = "invalid"
  }

  expect_failures = [var.sse_algorithm]
}

run "reject_invalid_object_ownership" {
  command = plan

  variables {
    s3_object_ownership = "invalid"
  }

  expect_failures = [var.s3_object_ownership]
}

run "reject_short_name" {
  command = plan

  variables {
    name = "ab"
  }

  expect_failures = [var.name]
}

run "reject_duplicate_rule_ids" {
  command = plan

  variables {
    lifecycle_rules = [
      for prefix in ["raw/", "failed/"] : {
        id                                     = "duplicate"
        prefix                                 = prefix
        expiration_days                        = 14
        noncurrent_expiration_days             = 7
        abort_incomplete_multipart_upload_days = 7
      }
    ]
  }

  expect_failures = [var.lifecycle_rules]
}

run "reject_fractional_retention" {
  command = plan

  variables {
    lifecycle_rules = [{
      id                                     = "raw-retention"
      prefix                                 = "raw/"
      expiration_days                        = 1.5
      noncurrent_expiration_days             = 7
      abort_incomplete_multipart_upload_days = 7
    }]
  }

  expect_failures = [var.lifecycle_rules]
}

run "bucket_outputs" {
  command = plan

  override_resource {
    target = module.bucket.aws_s3_bucket.default

    values = {
      id  = "event-analytics-test-123456789012"
      arn = "arn:aws:s3:::event-analytics-test-123456789012"
    }
  }

  assert {
    condition     = output.bucket_id == "event-analytics-test-123456789012"
    error_message = "bucket_id must forward the underlying bucket name."
  }

  assert {
    condition = (
      length(output.env_variables) == 1
      && output.env_variables[0].name == "S3_BUCKET"
      && output.env_variables[0].value == "event-analytics-test-123456789012"
    )
    error_message = "env_variables must expose the bucket name as S3_BUCKET."
  }

  assert {
    condition     = output.bucket_arn == "arn:aws:s3:::event-analytics-test-123456789012"
    error_message = "bucket_arn must forward the underlying bucket ARN."
  }
}
