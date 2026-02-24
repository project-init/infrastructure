# Terraform Modules - Agent Guidelines

This document captures architectural decisions and patterns for Terraform modules in this repository.

## Module Design Principles

### 1. No Provider Configurations in Child Modules

**Rule:** Modules under `terraform/modules/` are child modules and must NOT define their own provider configurations.

**Why:**
- Provider configurations in child modules are deprecated in Terraform
- Providers should be passed in from the root module
- This allows the caller to control provider configuration (regions, assume roles, etc.)

**Bad:**
```hcl
# modules/example/providers.tf - DO NOT DO THIS
provider "aws" {
  alias = "target"
  assume_role {
    role_arn = "arn:aws:iam::${var.account_id}:role/SomeRole"
  }
}
```

**Good:**
```hcl
# Root module passes provider to child module
module "example" {
  source = "./modules/example"
  providers = {
    aws.target = aws.target_account
  }
}
```

### 2. Provider Evaluation Timing

**Rule:** Never assume a role that depends on a resource being created in the same apply.

**Why:**
- Terraform evaluates provider configurations during the planning phase, before any resources are created
- If a provider's `assume_role` references an account/role that doesn't exist yet, the plan will fail

**Example Problem:**
```hcl
# This WILL NOT work - the account doesn't exist during provider evaluation
resource "aws_organizations_account" "this" {
  name = "new-account"
}

provider "aws" {
  alias = "new_account"
  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.this.id}:role/bootstrap"
  }
}
```

**Solution:** Use a two-stage approach:
1. First apply: Create the account
2. Second apply: Configure the account (with provider now able to assume the role)

Or use separate modules/states for account creation vs. account configuration.

### 3. Single Responsibility

**Rule:** Each module should do one thing well.

**Example - Account Lifecycle:**

| Module | Responsibility | Provider Context |
|--------|----------------|------------------|
| `account` | Create AWS Organizations account | Management Account |
| `account-baseline` | Configure account settings (alias, password policy, security services) | Target Account (via assumed role) |
| `account-networking` | Set up VPCs, subnets, etc. | Target Account |

### 4. Module Scope Boundaries

When deciding what belongs in a module, consider:

1. **Provider context** - Do all resources use the same provider/credentials?
2. **Lifecycle** - Are resources created/destroyed together?
3. **Dependencies** - Can resources be created in a single apply?

If the answer to any of these is "no," consider splitting into separate modules.

## Common Patterns

### Cross-Account Resources

For resources that span accounts (e.g., creating an account then configuring it):

```hcl
# Stage 1: Root module creates account
module "account" {
  source      = "./modules/account"
  namespace   = "analytics"
  environment = "production"
  email       = "analytics-prod@example.com"
}

# Stage 2: After apply, configure provider for new account
provider "aws" {
  alias = "analytics_prod"
  assume_role {
    role_arn = module.account.organization_role_arn
  }
}

# Stage 3: Baseline module configures the account
module "account_baseline" {
  source = "./modules/account-baseline"
  providers = {
    aws = aws.analytics_prod
  }
  # ... configuration
}
```

Note: Stages 1 and 2-3 typically require separate applies or use of `terraform apply -target`.

### Required Provider Aliases

If a module requires a specific provider alias, document it clearly:

```hcl
# modules/example/README.md
## Providers

This module requires the following provider configurations:

| Alias | Description |
|-------|-------------|
| `aws` | Default provider for the target account |
| `aws.management` | Provider for the management account (for Organizations APIs) |
```
