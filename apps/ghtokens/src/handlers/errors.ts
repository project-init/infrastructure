import { ConnectError, Code } from "@connectrpc/connect";
import { ConfigNotFoundError, DynamoDBError, RepositoryService } from "../services/repository.js";
import { OIDCValidatorService, JWTValidationError } from "../services/oidc.js";
import { AuthRulesEngine, AuthorizationError } from "../services/auth-rules.js";
import { GitHubAppService, GitHubAppError, SecretsManagerError } from "../services/github.js";
import { Effect } from "effect";

export const mapErrorToConnect = (error: unknown): ConnectError => {
  if (error instanceof ConnectError) {
    return error;
  }
  
  if (error instanceof ConfigNotFoundError) {
    return new ConnectError(
      `Configuration not found: ${error.namespace}/${error.name}`,
      Code.NotFound
    );
  }
  
  if (error instanceof AuthorizationError) {
    // Include minimal failed claim details, not the expected values for security
    const details = error.failedClaims.map(c => ({ claim: c.claim, result: c.result }));
    return new ConnectError(
      `Authorization failed. Failed claims: ${JSON.stringify(details)}`,
      Code.PermissionDenied
    );
  }
  
  if (error instanceof JWTValidationError) {
    return new ConnectError(
      "Invalid or expired OIDC token",
      Code.Unauthenticated
    );
  }
  
  if (error instanceof GitHubAppError) {
    return new ConnectError(
      `GitHub API error: ${error.message}`,
      Code.Internal
    );
  }
  
  if (error instanceof SecretsManagerError || error instanceof DynamoDBError) {
    return new ConnectError(
      "Internal server error",
      Code.Internal
    );
  }

  return new ConnectError("Unknown error occurred", Code.Unknown);
};

export const extractBearerToken = (req: { requestHeader: Headers }): string | undefined => {
  const authHeader = req.requestHeader.get("authorization");
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) {
    return undefined;
  }
  return authHeader.slice(7);
};
