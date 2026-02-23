# Account Bootstrap IAM Specification

## 1. Overview
**Purpose**: Configures the IAM foundation in a sibling account to allow the Platform Account to manage it. This replaces the dependency on the Management Account for day-to-day operations.

**Context**:
- Deployed into **Sibling Accounts**.
- Creates the `platform-execution` role.
- Enforces a "Reader" vs "Deployer" permission model based on session tags passed during `AssumeRole`.

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `platform_account_id` | `string` | **Required** | The AWS Account ID of the Platform Account. |
| `tags` | `map(string)` | `{}` | Additional tags to apply to resources. |

## 3. Resources

### `aws_iam_role` : `platform-execution`
- **Name**: `platform-execution`
- **Tags**: 
  - `PlatformManaged`: `true`
  - (Merge `var.tags`)
- **Trust Policy**:
  - **Principals**: 
    - `arn:aws:iam::<platform_account_id>:role/platform-reader-admin`
    - `arn:aws:iam::<platform_account_id>:role/platform-deployer-admin`
  - **Actions**:
    - `sts:AssumeRole`
    - `sts:TagSession`

### Permissions

#### 1. ReadOnly Access
- **Type**: Managed Policy Attachment
- **Policy ARN**: `arn:aws:iam::aws:policy/ReadOnlyAccess`
- **Attached To**: `platform-execution`

#### 2. Conditional Administrator Access
- **Type**: Inline Policy or Customer Managed Policy
- **Name**: `platform-execution-admin-access`
- **Statement**:
  - **Effect**: `Allow`
  - **Action**: `*`
  - **Resource**: `*`
  - **Condition**:
    - `StringEquals`:
      - `aws:PrincipalTag/Role`: `Deployer`

## 4. Outputs

| Name | Description |
|------|-------------|
| `role_arn` | ARN of the `platform-execution` role. |
| `role_name` | Name of the `platform-execution` role. |

## 5. Implementation Notes
- Ensure the Trust Policy explicitly allows both the Reader and Deployer roles from the Platform account.
- The `PlatformManaged=true` tag is critical for future Service Control Policies (SCPs) or Permission Boundaries to prevent tampering.
