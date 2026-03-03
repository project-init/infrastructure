# Module: aws/ghtokens

## Overview
The `ghtokens` module provisions the infrastructure for the GitHub Tokens Service, which provides secure, audited access to GitHub installation tokens for CI/CD workflows. It deploys an AWS Lambda function exposed via an HTTP Function URL and a DynamoDB table for token configurations and audit logs. The Lambda code (`.zip`) is automatically retrieved from a public Cloudflare R2 bucket containing service releases.

## Resources Created
| Resource | Description |
|----------|-------------|
| `aws_lambda_function` | The Lambda runtime executing the ghtokens service, deployed outside a VPC. The code (`.zip`) is dynamically pulled from a public R2 bucket. |
| `aws_lambda_function_url` | Exposes the Lambda function to the public internet via an HTTP endpoint without requiring API Gateway. |
| `aws_dynamodb_table` | Single-table design for storing Token Configurations and Audit Logs. Configured for On-Demand (PAY_PER_REQUEST) billing. |
| `module.iam_role` | Calls the `aws/iam-role` module to create the Lambda execution role. |
| `aws_iam_role_policy` | Inline or attached policies added to the IAM execution role granting access to DynamoDB (Read/Write) and Secrets Manager (Read-only for `/ghtokens/apps/*`). |

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `name_prefix` | `string` | | Yes | Prefix used for naming resources (e.g., `prod-ghtokens`). |
| `tags` | `map(string)` | `{}` | No | Standard tags applied to all resources created by this module. |
| `admin_github_app_id` | `string` | | Yes | The default admin GitHub App ID configured for the service. Exposed as an environment variable to the Lambda function. |

## Outputs
| Name | Description |
|------|-------------|
| `function_url` | The HTTP endpoint URL used to invoke the ghtokens service. |
| `dynamodb_table_name` | The name of the created DynamoDB table. |
| `lambda_function_name` | The name of the created Lambda function. |

## Dependencies
- Provider requirement: `aws` provider.
- Provider requirement: `http` provider (to fetch `versions.json` from the R2 bucket to determine the latest release).
- Module Dependency: This module calls the `aws/iam-role` module internally to create the Lambda execution role.

## Naming Convention
- Resources should be named using the `name_prefix` (e.g., `${var.name_prefix}-table`, `${var.name_prefix}-function`).

## Tagging
- All resources supporting tags must merge and apply `var.tags`.

## Usage Example
```hcl
module "ghtokens" {
  source = "../../aws/ghtokens"

  name_prefix         = "prod-ghtokens"
  tags                = { Environment = "prod", Service = "ghtokens" }
  admin_github_app_id = "123456"
}
```

## Implementation Notes
- **DynamoDB Key Schema**: The DynamoDB table must have `pk` (String) as the Partition Key and `sk` (String) as the Sort Key.
- **R2 Bucket Integration**: The R2 bucket URL must be hardcoded within the module during implementation. (Note for implementing agent: Prompt the user for this URL). The module must read `versions.json` from the bucket, parse it to extract the latest release version, and download the corresponding `.zip` file to use as the Lambda source code.
- **Secrets Manager**: The IAM policy created by this module should only grant `secretsmanager:GetSecretValue` and `secretsmanager:DescribeSecret` permissions to the Lambda Execution Role for ARNs matching `arn:aws:secretsmanager:<region>:<account>:secret:/ghtokens/apps/*`. The module itself does not provision any secrets.
- **Environment Variables**: The Lambda function should be configured with standard environment variables including the DynamoDB table name (`DYNAMODB_TABLE_NAME`) and the default admin GitHub App ID (`ADMIN_GITHUB_APP_ID`).

## Out of Scope
- This module does NOT create the Cloudflare R2 bucket.
- This module does NOT create the Secrets Manager secrets containing the actual GitHub App credentials.
