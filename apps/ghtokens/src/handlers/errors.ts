import { ConnectError, Code } from "@connectrpc/connect";
import {
  ConfigNotFoundError,
  DynamoDBError,
  JWTValidationError,
  AuthorizationError,
  GitHubAppError,
  SecretsManagerError,
} from "../services/errors.js";

export const mapErrorToConnect = (error: unknown): ConnectError => {
  if (error instanceof ConnectError) return error;

  const isTaggedError = typeof error === "object" && error !== null && "_tag" in error;
  const tag = isTaggedError ? (error as { _tag: string })._tag : undefined;

  if (tag === "ConfigNotFoundError" || error instanceof ConfigNotFoundError) {
    const err = error as ConfigNotFoundError;
    return new ConnectError(
      `Configuration not found: ${err.namespace}/${err.name}`,
      Code.NotFound,
    );
  }

  if (tag === "AuthorizationError" || error instanceof AuthorizationError) {
    const err = error as AuthorizationError;
    const isDebug = process.env.DEBUG_AUTH === "true";
    const details = err.failedClaims.map((c) => {
      if (isDebug) {
        return { claim: c.claim, expected: c.expected, actual: c.actual, result: c.result };
      }
      return { claim: c.claim, result: c.result };
    });
    return new ConnectError(
      `Authorization failed. Failed claims: ${JSON.stringify(details)}`,
      Code.PermissionDenied,
    );
  }

  if (tag === "JWTValidationError" || error instanceof JWTValidationError) {
    return new ConnectError("Invalid or expired OIDC token", Code.Unauthenticated);
  }

  if (tag === "GitHubAppError" || error instanceof GitHubAppError) {
    const err = error as GitHubAppError;
    return new ConnectError(`GitHub API error: ${err.message}`, Code.Internal);
  }

  if (tag === "SecretsManagerError" || tag === "DynamoDBError" || error instanceof SecretsManagerError || error instanceof DynamoDBError) {
    return new ConnectError("Internal server error", Code.Internal);
  }

  console.error("Unknown error mapping to ConnectError:", error);
  return new ConnectError("Unknown error occurred", Code.Unknown);
};

export const extractBearerToken = (ctx: { requestHeader: Headers }): string | undefined => {
  const authHeader = ctx.requestHeader.get("authorization");
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) {
    return undefined;
  }
  return authHeader.slice(7);
};

export const extractIamActor = (ctx: { requestHeader: Headers }): string => {
  const authHeader = ctx.requestHeader.get("authorization");
  if (!authHeader || !authHeader.startsWith("AWS4-HMAC-SHA256")) {
    throw new ConnectError("Missing IAM authentication (SigV4)", Code.Unauthenticated);
  }

  // Try common headers injected by AWS Lambda Web Adapter or API Gateway for IAM auth
  const actor =
    ctx.requestHeader.get("x-amzn-iam-principal") ||
    ctx.requestHeader.get("x-amzn-iam-arn") ||
    ctx.requestHeader.get("x-amzn-iam-user");
  
  if (!actor) {
    // If headers aren't present but SigV4 was used, fallback to a generic actor 
    // or parse the access key from the authorization header
    const match = authHeader.match(/Credential=([^/]+)\//);
    if (match && match[1]) {
      return `AWS:${match[1]}`;
    }
    throw new ConnectError("Could not determine IAM actor from request", Code.Unauthenticated);
  }
  return actor;
};
