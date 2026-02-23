# Module: eks-gha-runners

## Overview
This module provisions a low-cost EKS cluster using EKS auto mode and installs GitHub Actions Runner Controller (ARC) with runner scale sets that provide self-hosted runners for GitHub Actions workloads. It is designed to deploy into an existing VPC/subnets (default use case: shared VPC public subnets) while supporting private-only cluster endpoints for more mature network setups.

## Resources Created
| Resource | Description |
|----------|-------------|
| `aws_eks_cluster` | EKS cluster configured for auto mode. |
| `aws_eks_access_entry` | Access entries for admin SSO roles. |
| `aws_eks_access_policy_association` | Admin policy association for the access entries. |
| `aws_iam_role` | EKS cluster IAM role (if needed for auto mode). |
| `aws_iam_role_policy_attachment` | Attach required EKS managed policies to the cluster role. |
| `aws_security_group` | Cluster security group for the EKS control plane. |
| `kubernetes_secret` | Kubernetes secret with GitHub App credentials for ARC. |
| `helm_release` | ARC controller chart (`gha-runner-scale-set-controller`). |
| `helm_release` | ARC runner scale set chart per scale set (`gha-runner-scale-set`). |

## Data Sources
| Data source | Description |
|------------|-------------|
| `aws_secretsmanager_secret` | Read GitHub App credentials (existing secret). |

## Inputs
| Name | Type | Default | Required | Description |
|------|------|---------|----------|-------------|
| `organization` | `string` | - | Yes | Organization name used for naming and tagging. |
| `namespace` | `string` | `null` | No | Namespace for tagging (e.g., `platform`). |
| `environment` | `string` | `"global"` | No | Environment tag value. |
| `tags` | `map(string)` | `{}` | No | Additional tags to merge with standard tags. |
| `vpc_id` | `string` | - | Yes | VPC ID where the EKS cluster is deployed. |
| `subnet_ids` | `list(string)` | - | Yes | Subnet IDs where the EKS control plane network interfaces (ENIs) will be placed. These subnets may be public or private depending on your chosen endpoint/access pattern (default shared-VPC usage typically uses public subnets). |
| `eks_version` | `string` | `null` | No | EKS version. When null, use the provider default/latest supported version. |
| `cluster_public_access` | `bool` | `true` | No | Whether the EKS cluster endpoint is publicly accessible. |
| `cluster_public_access_cidrs` | `list(string)` | `["0.0.0.0/0"]` | No | Allowed CIDRs for public access (when enabled). Security warning: the default exposes the EKS API endpoint to the internet; most environments should override this with restricted CIDR ranges and/or set `cluster_public_access = false`. |
| `cluster_private_access` | `bool` | `true` | No | Whether the EKS cluster endpoint is privately accessible. |
| `github_organization` | `string` | - | Yes | GitHub organization name for ARC `githubConfigUrl`. |
| `github_app_secret_arn` | `string` | - | Yes | Secrets Manager ARN containing GitHub App credentials. |
| `arc_controller_namespace` | `string` | `"arc-systems"` | No | Namespace for ARC controller. |
| `arc_runners_namespace` | `string` | `"arc-runners"` | No | Namespace for runner scale sets. |
| `arc_controller_chart_version` | `string` | `null` | No | Helm chart version for `gha-runner-scale-set-controller`. When null, use the latest chart release. |
| `arc_runner_chart_version` | `string` | `null` | No | Helm chart version for `gha-runner-scale-set`. When null, use the latest chart release. |
| `runner_scale_sets` | `list(object({ enabled = bool, name = string, description = string, cpu = string, memory = string, min = optional(number, null), max = optional(number, null), repositories = optional(list(string), null) }))` | See defaults | No | Runner scale set configuration. `repositories` is accepted but ignored for now (org-level runners only). |
| `admin_principal_arn_patterns` | `list(string)` | `["arn:aws:iam::*:role/AWSReservedSSO_Operator_*", "arn:aws:iam::*:role/AWSReservedSSO_Admin_*"]` | No | IAM principal ARN patterns used to discover SSO roles that should get cluster-admin access. |

### Default `runner_scale_sets`
The module defines the following default list with `min`/`max` unset (ARC defaults):
- `k8s-amd64-sm` (1cpu/4Gi)
- `k8s-amd64-default` (2cpu/8Gi)
- `k8s-amd64-large` (4cpu/16Gi)
- `k8s-arm64-sm` (1cpu/4Gi)
- `k8s-arm64-default` (2cpu/8Gi)
- `k8s-arm64-large` (4cpu/16Gi)
- `k8s-sm` (1cpu/4Gi, arm64-only naming)
- `k8s` (2cpu/8Gi, arm64-only naming)
- `k8s-default` (2cpu/8Gi, arm64-only naming)
- `k8s-large` (4cpu/16Gi, arm64-only naming)

## Outputs
| Name | Description |
|------|-------------|
| `cluster_name` | EKS cluster name. |
| `cluster_arn` | EKS cluster ARN. |
| `cluster_endpoint` | EKS cluster endpoint. |
| `cluster_security_group_id` | Cluster security group ID to share via RAM for downstream access. |
| `cluster_ca_data` | Cluster CA data for Kubernetes/Helm providers. |
| `cluster_auth_token` | EKS authentication token (generated) for Kubernetes/Helm providers. |
| `cluster_oidc_issuer` | OIDC issuer URL. |
| `cluster_oidc_provider_arn` | OIDC provider ARN (if created or read). |
| `arc_controller_namespace` | Namespace used for ARC controller. |
| `arc_runners_namespace` | Namespace used for ARC runners. |
| `runner_scale_set_names` | Names of runner scale sets created. |

## Dependencies
- Requires the default AWS provider for the target region.
- Root module must configure `kubernetes` and `helm` providers using this module’s outputs (token, endpoint, CA).

## Naming Convention
- EKS cluster name: `<organization>-gha-runners`.
- Helm releases: `arc` for controller; `arc-<scale_set_name>` for each scale set.

## Tagging
Standard tags applied to AWS resources:
- `Organization` from `var.organization`
- `Namespace` from `var.namespace` (if provided)
- `Environment` from `var.environment`
Additional tags from `var.tags` are merged.

## Usage Example
```hcl
module "gha_runners" {
  source = "./modules/eks-gha-runners"

  organization        = "acme"
  namespace           = "platform"
  environment         = "global"
  vpc_id              = "vpc-xxxx"
  subnet_ids          = ["subnet-aaaa", "subnet-bbbb"]
  github_organization = "acme"
  github_app_secret_arn = "arn:aws:secretsmanager:us-east-1:123456789012:secret:gha-app"
}

provider "kubernetes" {
  host                   = module.gha_runners.cluster_endpoint
  cluster_ca_certificate = base64decode(module.gha_runners.cluster_ca_data)
  token                  = module.gha_runners.cluster_auth_token
}

provider "helm" {
  kubernetes {
    host                   = module.gha_runners.cluster_endpoint
    cluster_ca_certificate = base64decode(module.gha_runners.cluster_ca_data)
    token                  = module.gha_runners.cluster_auth_token
  }
}
```

## Implementation Notes
- Use EKS auto mode only; no managed or self-managed node groups.
- Minimize add-ons to what auto mode requires to keep costs low.
- ARC charts are OCI-based (`oci://ghcr.io/actions/actions-runner-controller-charts/gha-runner-scale-set-controller` and `.../gha-runner-scale-set`).
- Use GitHub App auth with a Kubernetes secret created from Secrets Manager values. Expected JSON keys: `app_id`, `installation_id`, `private_key`.
- Build `githubConfigUrl` as `https://github.com/<github_organization>`.
- `repositories` in `runner_scale_sets` is accepted but ignored for now (org-wide scale sets only).
- Discover admin SSO roles by pattern match and create EKS access entries with cluster-admin access for each.

## Out of Scope
- Creating or modifying the VPC, subnets, or route tables.
- Creating GitHub Apps or Secrets Manager secrets.
- Custom runner images or node scheduling rules.
- Repo-scoped runner scale sets (only org-level runners in this module).
