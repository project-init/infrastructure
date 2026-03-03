import { Data } from "effect";

export class DynamoDBError extends Data.TaggedError("DynamoDBError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}

export class ConfigNotFoundError extends Data.TaggedError("ConfigNotFoundError")<{
  readonly namespace: string;
  readonly name: string;
}> {}

export class JWTValidationError extends Data.TaggedError("JWTValidationError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}

export class AuthorizationError extends Data.TaggedError("AuthorizationError")<{
  readonly message: string;
  readonly failedClaims: ReadonlyArray<{
    readonly claim: string;
    readonly expected: readonly string[];
    readonly actual: string | undefined;
    readonly result: "denied";
  }>;
}> {}

export class SecretsManagerError extends Data.TaggedError("SecretsManagerError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}

export class GitHubAppError extends Data.TaggedError("GitHubAppError")<{
  readonly message: string;
  readonly cause: unknown;
}> {}
