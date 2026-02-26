import { Context, Effect, Layer } from "effect";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { Schema } from "@effect/schema";
import { Octokit } from "@octokit/core";
import { createAppAuth } from "@octokit/auth-app";
import { Cache } from "effect";

export class SecretsManagerError extends Schema.TaggedError<SecretsManagerError>()("SecretsManagerError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

export class GitHubAppError extends Schema.TaggedError<GitHubAppError>()("GitHubAppError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

export const AppCredentials = Schema.Struct({
  app_id: Schema.String,
  private_key: Schema.String,
  installation_id: Schema.String,
  webhook_secret: Schema.optionalWith(Schema.String, { exact: true }),
});
export type AppCredentials = Schema.Schema.Type<typeof AppCredentials>;

export interface SecretsManagerService {
  readonly getAppCredentials: (appId: string) => Effect.Effect<AppCredentials, SecretsManagerError>;
}
export const SecretsManagerService = Context.GenericTag<SecretsManagerService>("@ghtokens/SecretsManagerService");

export const makeSecretsManagerService = (client: SecretsManagerClient): SecretsManagerService => {
  return {
    getAppCredentials: (appId: string) => Effect.tryPromise({
      try: async () => {
        const response = await client.send(new GetSecretValueCommand({
          SecretId: `/ghtokens/apps/${appId}`
        }));
        if (!response.SecretString) {
          throw new Error("SecretString is empty");
        }
        return JSON.parse(response.SecretString) as AppCredentials;
      },
      catch: (e) => new SecretsManagerError({ message: `Failed to fetch credentials for app ${appId}`, cause: e })
    })
  };
};

export const SecretsManagerLayer = Layer.effect(
  SecretsManagerService,
  Effect.gen(function* () {
    const client = new SecretsManagerClient({});
    return makeSecretsManagerService(client);
  })
);

export interface TokenResult {
  readonly token: string;
  readonly expiresAt: string;
}

export interface GitHubAppService {
  readonly getInstallationToken: (
    appId: string, 
    repositories: string[], 
    permissions: Record<string, string>
  ) => Effect.Effect<TokenResult, GitHubAppError | SecretsManagerError>;
}
export const GitHubAppService = Context.GenericTag<GitHubAppService>("@ghtokens/GitHubAppService");

export const GitHubAppLayer = Layer.effect(
  GitHubAppService,
  Effect.gen(function* () {
    const secretsManager = yield* SecretsManagerService;

    // Cache to store credentials so we don't hit SecretsManager repeatedly
    const credsCache = yield* Cache.make({
      capacity: 100,
      timeToLive: "1 hours",
      lookup: (appId: string) => secretsManager.getAppCredentials(appId)
    });

    // Cache to store installation tokens to avoid hitting GitHub API repeatedly
    const tokenCache = yield* Cache.make({
      capacity: 1000,
      timeToLive: "4 minutes", // Slightly less than the 5m GitHub token cache standard
      lookup: (key: string) => Effect.gen(function* () {
        const { appId, repositories, permissions } = JSON.parse(key) as {
          appId: string,
          repositories: string[],
          permissions: Record<string, string>
        };

        const creds = yield* credsCache.get(appId);

        const octokit = new Octokit({
          authStrategy: createAppAuth,
          auth: {
            appId: creds.app_id,
            privateKey: creds.private_key,
            installationId: creds.installation_id,
          }
        });

        const response = yield* Effect.tryPromise({
          try: () => octokit.request("POST /app/installations/{installation_id}/access_tokens", {
            installation_id: parseInt(creds.installation_id, 10),
            repositories: repositories,
            permissions: permissions,
          }),
          catch: (e) => new GitHubAppError({ message: "Failed to generate installation token", cause: e })
        });

        return {
          token: response.data.token,
          expiresAt: response.data.expires_at,
        } as TokenResult;
      })
    });

    return {
      getInstallationToken: (appId, repositories, permissions) => {
        // Create a deterministic cache key
        const key = JSON.stringify({
          appId,
          repositories: [...repositories].sort(),
          permissions: Object.keys(permissions).sort().reduce((acc, k) => ({ ...acc, [k]: permissions[k] }), {})
        });
        
        return tokenCache.get(key);
      }
    };
  })
);
