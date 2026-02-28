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

  if (error instanceof ConfigNotFoundError) {
    return new ConnectError(
      `Configuration not found: ${error.namespace}/${error.name}`,
      Code.NotFound,
    );
  }

  if (error instanceof AuthorizationError) {
    const isDebug = process.env.DEBUG_AUTH === "true";
    const details = error.failedClaims.map((c) => {
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

  if (error instanceof JWTValidationError) {
    return new ConnectError("Invalid or expired OIDC token", Code.Unauthenticated);
  }

  if (error instanceof GitHubAppError) {
    return new ConnectError(`GitHub API error: ${error.message}`, Code.Internal);
  }

  if (error instanceof SecretsManagerError || error instanceof DynamoDBError) {
    return new ConnectError("Internal server error", Code.Internal);
  }

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
