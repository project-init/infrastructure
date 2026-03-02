# GitHub Tokens Service (`ghtokens`)

The `ghtokens` service provides a secure, centralized API for minting short-lived GitHub App Installation Tokens. It uses GitHub Actions OIDC tokens for authentication and authorization, allowing CI/CD workflows to securely request scoped GitHub access without needing to store long-lived credentials.

## Overview

In modern CI/CD, managing long-lived secrets like Personal Access Tokens (PATs) or GitHub App Private Keys poses a significant security risk. The `ghtokens` service solves this by:

1. **Leveraging OIDC**: CI pipelines (like GitHub Actions) can authenticate using short-lived OIDC tokens.
2. **Centralized Authorization**: `ghtokens` evaluates the claims in the OIDC token against administrator-defined rules (e.g., verifying the repository, branch, or workflow requesting the token).
3. **Just-in-Time Token Minting**: If authorized, `ghtokens` requests a scoped, short-lived installation token from a GitHub App and returns it to the pipeline.
4. **Audit Logging**: Every token request (and denial) is logged centrally for security and compliance.

## Architecture

This service is built using:
- **Bun** / **TypeScript**
- **Effect-TS**: For functional, robust error handling and dependency injection.
- **ConnectRPC**: To provide a gRPC / Protobuf based API with broad client compatibility (including JSON over HTTP).
- **AWS DynamoDB**: For storing token configurations and audit logs.
- **AWS Secrets Manager**: For securely storing the underlying GitHub App private keys.

## API Services

The service exposes two primary RPC interfaces via ConnectRPC:

### 1. `TokenService`
Used by CI/CD clients to request tokens.
- **`GetToken`**: Exchanges a valid OIDC JWT for a scoped GitHub installation token.
- **`DryRun`**: Validates an OIDC token against a specific configuration to verify if a token *would* be granted, without actually minting one. Useful for debugging auth rules.

### 2. `AdminService`
Used by administrators to manage configurations. All endpoints require IAM Signature V4 authentication.
- **`CreateConfiguration`**: Create a new token mapping configuration.
- **`GetConfiguration`**: Retrieve an existing configuration.
- **`UpdateConfiguration`**: Update configuration details, permissions, or auth rules.
- **`DeleteConfiguration`**: Delete a configuration.
- **`ListConfigurations`**: List all configurations (optionally filtered by namespace).

## Configuration and Auth Rules

A Configuration defines the rules that determine *who* can get a token and *what* permissions the token will have. It consists of:

- **Namespace & Name**: Unique identifier for the configuration.
- **GitHub App ID**: The GitHub App to use for minting the token.
- **Auth Rules**: A set of criteria evaluated against OIDC token claims.
- **Repositories**: A list of repositories the minted token will have access to. Supports wildcards (e.g., `project-init/*`) and macros (e.g., `@current` to map to the repo executing the action).
- **Permissions**: Granular GitHub API permissions (e.g., `contents: read`, `issues: write`) to request for the token.

### Example Auth Rules
```json
{
  "repository": ["project-init/frontend", "project-init/backend"],
  "ref": ["refs/heads/main"],
  "event_name": ["push", "pull_request"]
}
```
*In this example, the OIDC token must originate from either the frontend or backend repository, triggered on the main branch, by a push or PR event.*

## Local Development

You can run the service and its dependencies locally using Docker Compose via `mise`.

### 1. Start dependencies
This spins up LocalStack (DynamoDB and Secrets Manager) and runs an initialization script to set up tables and mock secrets.
```bash
mise c up -d
```

### 2. View Logs
```bash
mise c logs -f ghtokens
```

### 3. Run Integration Tests
We provide a comprehensive suite of integration tests that can be run against the local development server:
```bash
bun test apps/ghtokens/integration/api.test.ts
```

#### Smoke Tests
The integration suite can be run in "read-only" mode, skipping all mutative operations (create, update, delete). This is useful for running safe smoke tests against staging or production environments.
```bash
SMOKE_TEST=true API_BASE_URL="https://your-api.url" bun test apps/ghtokens/integration/api.test.ts
```

## Security & IAM Integration

The `AdminService` uses AWS IAM Signature Version 4 for authentication. If running behind an AWS API Gateway or using AWS Lambda Web Adapter, the IAM headers are passed directly to the service to extract the authenticated principal and authorize admin requests.