# Platform Bootstrap IAM Specification

## 1. Overview
**Purpose**: Creates the "Jump Host" roles in the Platform Account that users (via `credential_process`) assume to manage the rest of the infrastructure. These roles enforce strict session tagging to propagate permissions ("Reader" vs "Deployer") downstream.

**Context**:
- Deployed into the **Platform Account**.
- Creates `platform-reader-admin` and `platform-deployer-admin`.
- Interacts with a local `credential_process` script that performs the initial `AssumeRole` with transitive tags.

## 2. Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `allowed_principals` | `list(string)` | **Required** | List of ARNs (SSO Roles or Users) allowed to assume these roles. |
| `tags` | `map(string)` | `{}` | Additional tags to apply. |

## 3. Resources

### `aws_iam_role`: `platform-reader-admin`
- **Trust Policy**:
  - **Effect**: `Allow`
  - **Principals**: `var.allowed_principals`
  - **Actions**: `sts:AssumeRole`, `sts:TagSession`
  - **Condition**:
    - `StringEquals`: `aws:RequestTag/Role`: `Reader`
- **Permissions Policy**:
  - **Effect**: `Allow`
  - **Action**: `sts:AssumeRole`, `sts:TagSession`
  - **Resource**: `arn:aws:iam::*:role/platform-execution`
  - **Condition**:
    - `StringEquals`: `aws:RequestTag/Role`: `Reader`
    - `ForAllValues:StringLike`: `aws:TagKeys`: `Role` (Enforce passing the tag transitively)

### `aws_iam_role`: `platform-deployer-admin`
- **Trust Policy**:
  - **Effect**: `Allow`
  - **Principals**: `var.allowed_principals`
  - **Actions**: `sts:AssumeRole`, `sts:TagSession`
  - **Condition**:
    - `StringEquals`: `aws:RequestTag/Role`: `Deployer`
- **Permissions Policy**:
  - **Effect**: `Allow`
  - **Action**: `sts:AssumeRole`, `sts:TagSession`
  - **Resource**: `arn:aws:iam::*:role/platform-execution`
  - **Condition**:
    - `StringEquals`: `aws:RequestTag/Role`: `Deployer`
    - `ForAllValues:StringLike`: `aws:TagKeys`: `Role` (Enforce passing the tag transitively)

## 4. Outputs

| Name | Description |
|------|-------------|
| `reader_role_arn` | ARN of `platform-reader-admin` |
| `deployer_role_arn` | ARN of `platform-deployer-admin` |

## 5. Implementation Notes
- The Trust Policy conditions ensure that the `credential_process` script *must* pass the tag `Role=<level>` during the initial assumption.
- The Permission Policy conditions ensure that when this role acts (jumps downstream), it *must* continue to pass the specific tag `Role=<level>`.
- `PlatformManaged=true` tag should be applied to these roles.
