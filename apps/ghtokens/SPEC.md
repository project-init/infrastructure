# GitHub Tokens Service (ghtokens)

## Overview

The GitHub Tokens Service provides secure, audited access to GitHub installation tokens for CI/CD workflows. It validates GitHub OIDC tokens against configurable authorization rules and issues scoped installation tokens via GitHub Apps.

## Problem Statement

GitHub Actions workflows often need to perform cross-repository operations (cloning other repos, creating PRs, triggering workflows). The standard `GITHUB_TOKEN` is scoped to the current repository only. Personal Access Tokens (PATs) solve this but have drawbacks:

- Tied to individual users (security risk if user leaves)
- Difficult to audit and rotate
- Overly broad permissions
- No way to restrict which workflows can use them

**Solution**: Use GitHub Apps with fine-grained permissions, combined with OIDC-based authentication to verify workflow identity before issuing tokens.

## How It Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GitHub Actions Workflow                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    1. Request OIDC token from GitHub
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         GitHub OIDC Provider                                 │
│  Returns JWT with claims: repository, actor, ref, workflow, environment...  │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    2. Send OIDC token + config name to ghtokens
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          ghtokens Service                                    │
│                                                                              │
│  a. Validate JWT signature against GitHub's JWKS                            │
│  b. Look up token configuration by namespace/name                           │
│  c. Check if JWT claims match the auth rules                                │
│  d. If authorized, request installation token from GitHub App               │
│  e. Return scoped installation token to workflow                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    3. Return installation token
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GitHub Actions Workflow                            │
│              Uses installation token to access other repositories            │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Example workflow usage**:
```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write  # Required for OIDC
    steps:
      - name: Get installation token
        id: token
        run: |
          OIDC_TOKEN=$(curl -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
            "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=ghtokens" | jq -r '.value')
          
          RESPONSE=$(curl -X POST https://ghtokens.example.com/ghtokens.v1.TokenService/GetToken \
            -H "Authorization: Bearer $OIDC_TOKEN" \
            -H "Content-Type: application/json" \
            -d '{"namespace": "deploy", "name": "infrastructure"}')
          
          echo "token=$(echo $RESPONSE | jq -r '.token')" >> $GITHUB_OUTPUT
      
      - name: Clone private repo
        run: |
          git clone https://x-access-token:${{ steps.token.outputs.token }}@github.com/org/private-repo.git
```

## Architecture

### Deployment Model

- **Runtime**: AWS Lambda with Function URL
- **Region**: Single region deployment
- **API Protocol**: Connect RPC over HTTP (protobuf)
- **Authentication**:
  - Token endpoint: GitHub OIDC JWT in `Authorization` header
  - Admin CRUD endpoints: AWS IAM authentication (SigV4)

### Data Stores

- **DynamoDB**: Token configurations and audit logs (single table design)
- **Secrets Manager**: GitHub App credentials at `/ghtokens/apps/{app-id}`

## Token Configuration

A token configuration defines who can request tokens and what permissions those tokens have.

### Schema

```
TokenConfiguration {
  namespace: string          # Free-form grouping (e.g., "ci", "deploy", "team-a")
  name: string               # Unique name within namespace
  description: string        # Human-readable purpose
  
  github_app_id?: string     # Optional override; defaults to admin app
  
  auth: AuthRules            # OIDC claim matching rules
  repositories: string[]     # Repos to grant access (supports wildcards)
  permissions: Permissions   # GitHub permission grants
  
  created_at: timestamp
  updated_at: timestamp
  created_by: string
  updated_by: string
}
```

### DynamoDB Key Structure

Single-table design with the following key schema for token configurations:

- **Partition key (`pk`)**: `CFG#{namespace}`
- **Sort key (`sk`)**: `{name}`

This enables:
- Fetch single config: `pk = "CFG#deploy"` AND `sk = "infrastructure"`
- List configs in namespace: `pk = "CFG#deploy"` (query)
- List all configs: Scan with `pk` begins_with `"CFG#"`

### Auth Rules

Auth rules define which GitHub OIDC claims must match for a token request to be authorized.

**Evaluation Logic**:
- Across different claims: rules are AND'd (all configured claims must pass)
- A claim not configured in auth rules is not checked (implicit allow)
- If a configured claim is missing from the OIDC token, the rule **fails**

**Per-Claim Evaluation** (order matters):
1. **Negation check first**: If any negated pattern (e.g., `!test-user`) matches the actual claim value, the claim **fails immediately**
2. **Positive pattern check**: If there are any positive (non-negated) patterns, at least one must match for the claim to pass
3. **Negation-only rules**: If a claim rule contains only negations, the claim passes if none of the negated patterns match

This ensures negations act as blocklists that cannot be bypassed by other patterns.

**Supported Claims**:
- `repository` - Full org/repo format (e.g., `your-org/infrastructure`)
- `actor` - GitHub username triggering the workflow
- `job_workflow_ref` - Reusable workflow reference
- `ref` - Git ref (branch/tag, e.g., `refs/heads/main`)
- `event_name` - Trigger event (`push`, `pull_request`, `workflow_dispatch`, etc.)
- `environment` - GitHub environment name

**Pattern Syntax**:
- Exact match: `"deploy-bot"`
- Negation: `"!test-user"` (blocklist - checked first, causes immediate failure if matched)
- Wildcard: IAM-style wildcards (`*` matches any characters, including internal)
  - `"your-org/*"` matches any repo in org
  - `"your-org/infra-*"` matches repos starting with `infra-`
  - `"!your-org/secret-*"` blocks any repo starting with `secret-` (negation + wildcard)
- Macro `@current`: Represents the calling repository from the OIDC token
  - In `repository` auth claim: expands to full `{org}/{repo}` format, used to restrict a config to only be usable by workflows in specific repos
  - In `repositories` grant list: expands to `{repo}` only, used to grant the token access back to the calling repo

**Example**:
```yaml
auth:
  actor: ["deploy-bot", "!test-user"]
  repository: ["your-org/infrastructure", "your-org/shared-*"]
  job_workflow_ref: ["your-org/infrastructure/.github/workflows/*.yaml@refs/heads/main"]
  ref: ["refs/heads/main", "refs/tags/v*"]
  event_name: ["push", "workflow_dispatch"]
```

**Example Evaluations**:

*Example 1: Successful authorization*

Given OIDC claims:
```json
{
  "actor": "deploy-bot",
  "repository": "your-org/infrastructure",
  "ref": "refs/heads/main",
  "event_name": "push",
  "job_workflow_ref": "your-org/infrastructure/.github/workflows/deploy.yaml@refs/heads/main"
}
```

Against the auth rules above:
1. `actor`: Check negations first - "deploy-bot" != "test-user", no block. Then check positive patterns - matches "deploy-bot" -> **PASS**
2. `repository`: matches "your-org/infrastructure" exactly -> **PASS**
3. `ref`: matches "refs/heads/main" -> **PASS**
4. `event_name`: matches "push" -> **PASS**
5. `job_workflow_ref`: matches wildcard pattern -> **PASS**

Result: **AUTHORIZED**

*Example 2: Blocked by negation*

Given OIDC claims:
```json
{
  "actor": "test-user",
  "repository": "your-org/infrastructure",
  "ref": "refs/heads/main",
  "event_name": "push",
  "job_workflow_ref": "your-org/infrastructure/.github/workflows/deploy.yaml@refs/heads/main"
}
```

1. `actor`: Check negations first - "test-user" matches "!test-user" -> **FAIL (blocked)**

Result: **DENIED** (negation matched, even though "test-user" might match a wildcard pattern if one existed)

*Example 3: Missing required claim*

Given OIDC claims:
```json
{
  "actor": "deploy-bot",
  "repository": "your-org/infrastructure",
  "ref": "refs/heads/main",
  "event_name": "push"
}
```

1-4. All present claims pass
5. `job_workflow_ref`: claim not present in OIDC token, but rule requires it -> **FAIL**

Result: **DENIED** (configured claim missing from token)

### Repositories

List of repositories the installation token should have access to. These are repository names only (not org/repo format). Supports IAM-style wildcards.

```yaml
repositories:
  - "infrastructure"
  - "shared-*"
  - "@current"  # Resolves to requesting repo name (e.g., if request comes from your-org/my-app, resolves to "my-app")
```

**Note**: The GitHub App must be installed on these repositories for the token to have access.

### Permissions

Uses GitHub's native permission names and levels.

```yaml
permissions:
  contents: "read"
  issues: "write"
  pull_requests: "write"
  actions: "read"
```

## GitHub App Configuration

GitHub Apps provide fine-grained, auditable access to repositories without being tied to a user account.

### Setup Requirements

1. Create a GitHub App in your organization with desired permissions
2. Install the app on repositories it needs to access
3. Store the app credentials in AWS Secrets Manager

### Multi-App Support

- A default admin GitHub App is required (configured at deployment time)
- Individual token configurations can override with a different `github_app_id`
- Use case: different teams can have isolated apps with separate audit trails

### Secrets Manager Schema

Path: `/ghtokens/apps/{app-id}`

```json
{
  "app_id": "123456",
  "private_key": "-----BEGIN RSA PRIVATE KEY-----\n...",
  "installation_id": "78901234",
  "webhook_secret": "optional-webhook-secret"
}
```

## API Specification

### Token Endpoint

**POST /ghtokens.v1.TokenService/GetToken**

Request:
```protobuf
message GetTokenRequest {
  string namespace = 1;
  string name = 2;
}
```

Response:
```protobuf
message GetTokenResponse {
  string token = 1;
  google.protobuf.Timestamp expires_at = 2;
  repeated string repositories = 3;
  map<string, string> permissions = 4;
}
```

Authentication: GitHub OIDC JWT in `Authorization: Bearer <token>` header

**POST /ghtokens.v1.TokenService/DryRun**

Tests whether a token request would be authorized without actually issuing a token. Useful for validating auth rules during development or debugging.

Request (same as GetToken):
```protobuf
message DryRunRequest {
  string namespace = 1;
  string name = 2;
}
```

Response:
```protobuf
message DryRunResponse {
  bool authorized = 1;
  repeated string matched_claims = 2;   // Claims that passed evaluation
  repeated string failed_claims = 3;    // Claims that failed (with reason)
}
```

Note: DryRun uses a separate response type since it returns authorization diagnostics rather than an actual token.

### Admin CRUD Endpoints

All admin endpoints require IAM authentication (SigV4).

**POST /ghtokens.v1.AdminService/CreateConfiguration**
**POST /ghtokens.v1.AdminService/GetConfiguration**
**POST /ghtokens.v1.AdminService/UpdateConfiguration**
**POST /ghtokens.v1.AdminService/DeleteConfiguration**
**POST /ghtokens.v1.AdminService/ListConfigurations**

### Health Endpoint

**GET /health** - Simple health check (no auth required)

## Error Handling

### Internal Errors (Effect)

Use Effect's tagged error unions for precise error handling:

- `ConfigNotFoundError`
- `AuthorizationError` (with failed claim details)
- `GitHubAppError`
- `SecretsManagerError`
- `DynamoDBError`
- `JWTValidationError`

### External Errors (Connect RPC)

Map Effect errors to Connect RPC codes at the API boundary:

| Effect Error | Connect Code | Details |
|--------------|--------------|---------|
| ConfigNotFoundError | NOT_FOUND | Configuration does not exist |
| AuthorizationError | PERMISSION_DENIED | Include which claims failed |
| JWTValidationError | UNAUTHENTICATED | Invalid or expired OIDC token |
| GitHubAppError | INTERNAL | GitHub API failure |
| SecretsManagerError | INTERNAL | Secrets retrieval failure |
| DynamoDBError | INTERNAL | Database failure |

**403 Response Security**:

By default, authorization failures return only which claims failed, **not** the expected patterns (to avoid leaking internal policy):

```json
{
  "code": "PERMISSION_DENIED",
  "message": "Authorization failed",
  "details": [
    {"claim": "actor", "result": "denied"},
    {"claim": "ref", "result": "denied"}
  ]
}
```

**Debug mode** (admin-only, enabled per-config or via environment): Returns full pattern details for troubleshooting:

```json
{
  "code": "PERMISSION_DENIED", 
  "message": "Authorization failed",
  "details": [
    {"claim": "actor", "expected": ["deploy-bot", "!test-user"], "actual": "other-user", "result": "denied"},
    {"claim": "ref", "expected": ["refs/heads/main"], "actual": "refs/heads/feature", "result": "denied"}
  ]
}
```

The DryRun endpoint always returns full details since it requires a valid OIDC token from an authorized caller.

## Caching

### Installation Token Cache

- **Duration**: 5 minutes
- **Key**: `{app_id}:{repositories_hash}:{permissions_hash}`
- **Storage**: In-memory (Lambda instance)
- **Behavior**: Return cached token if not expired; otherwise fetch new token from GitHub

## Audit Logging

All configuration changes and token requests are logged to DynamoDB.

### Audit Record Schema

```
AuditRecord {
  pk: "AUDIT#{namespace}#{name}"
  sk: "{timestamp}#{event_id}"
  
  event_type: "CREATE" | "UPDATE" | "DELETE" | "TOKEN_REQUEST" | "TOKEN_DENIED"
  actor: string           # IAM principal or GitHub actor
  timestamp: ISO8601
  
  # For config changes
  previous_value?: TokenConfiguration
  new_value?: TokenConfiguration
  
  # For token requests
  oidc_claims?: map<string, string>
  matched_rules?: string[]
  failed_rules?: string[]
}
```

## Technology Stack

### Runtime & Framework

- **Runtime**: Bun
- **Framework**: Effect-TS ecosystem
  - `effect` - Core functional effect system
  - `@effect/schema` - Schema validation and parsing
  - `@effect/platform` - HTTP and platform utilities

### API

- **Protocol**: Connect RPC (protobuf)
- **Schema**: Buf for protobuf management
- **Implementation**: `@connectrpc/connect` with Bun adapter

### AWS Integration

- AWS SDK v3 with Effect wrappers
- DynamoDB for data storage
- Secrets Manager for GitHub App credentials
- Lambda with Function URL

### GitHub Integration

- `@octokit/core` wrapped in Effect service
- `jose` for JWT/OIDC validation

---

# Shared Packages

## packages/proto

Protobuf definitions and generated TypeScript code.

### Structure

```
packages/proto/
  buf.yaml
  buf.gen.yaml
  src/
    ghtokens/
      v1/
        token.proto
        admin.proto
        common.proto
  gen/
    # Generated TypeScript code
```

### Usage

Internal only - not published to npm.

## packages/github

Effect-native GitHub client built on `@octokit/core`.

### Features

- Effect-wrapped Octokit operations
- GitHub App authentication
- Installation token generation
- Typed error handling

### Services

```typescript
// GitHubAppService - manages app authentication
// InstallationService - manages installation tokens
// Layer composition for dependency injection
```

## packages/oidc

GitHub OIDC token validation and claim extraction.

### Features

- JWT validation using `jose`
- JWKS fetching and caching
- Claim extraction and typing
- Effect-native error handling

### Services

```typescript
// OIDCValidatorService - validates GitHub OIDC tokens
// ClaimsService - extracts and types claims
```

## packages/auth-rules

Authorization rule matching engine.

### Features

- Pattern matching (exact, negation, wildcards)
- `@current` macro expansion
- IAM-style wildcard evaluation
- Rule evaluation with detailed results

---

# CLI Tool

## apps/ghtokens-cli

Simple CLI for managing token configurations.

### Commands

```bash
ghtokens config create --namespace <ns> --name <name> --file <config.yaml>
ghtokens config get --namespace <ns> --name <name>
ghtokens config update --namespace <ns> --name <name> --file <config.yaml>
ghtokens config delete --namespace <ns> --name <name>
ghtokens config list [--namespace <ns>]
```

### Authentication

Uses AWS credentials from environment/profile for IAM auth to admin endpoints.

---

# Directory Structure

```
infrastructure/
  apps/
    ghtokens/           # Main Lambda service
      SPEC.md
      src/
        handlers/       # Connect RPC handlers
        services/       # Effect services
        repository/     # DynamoDB operations
      package.json
    ghtokens-cli/       # CLI tool
      src/
      package.json
  packages/
    proto/              # Protobuf definitions
    github/             # Effect GitHub client
    oidc/               # OIDC validation
    auth-rules/         # Rule matching engine
  proto/                # Source .proto files
    buf.yaml
    buf.gen.yaml
    ghtokens/
      v1/
        token.proto
        admin.proto
  package.json          # Workspace root
```

---

# Design Decisions

1. **GitHub JWKS URL**: Hardcoded to `https://token.actions.githubusercontent.com/.well-known/jwks` - only github.com is supported.

2. **Default Admin App**: A default GitHub App is required and configured at deployment time. Token configs can optionally override with `github_app_id`.

3. **Audit Retention**: No TTL - audit records are retained indefinitely.

4. **Config Validation**: No validation of repository existence - configs can reference any repository names including those not yet created.
