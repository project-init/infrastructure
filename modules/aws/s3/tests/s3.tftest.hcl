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
    force_destroy      = true
    versioning_enabled = false
  }
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
