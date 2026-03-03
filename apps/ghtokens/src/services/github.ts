import { Context, Effect, Layer, Cache } from "effect";
import { SecretsManagerClient, GetSecretValueCommand } from "@aws-sdk/client-secrets-manager";
import { Octokit } from "@octokit/core";
import { createAppAuth } from "@octokit/auth-app";
import { SecretsManagerError, GitHubAppError } from "./errors.js";

export interface AppCredentials {
  readonly app_id: string;
  readonly private_key: string;
  readonly installation_id: string;
  readonly webhook_secret?: string;
}

export interface SecretsManagerService {
  readonly getAppCredentials: (appId: string) => Effect.Effect<AppCredentials, SecretsManagerError>;
}
export const SecretsManagerService = Context.GenericTag<SecretsManagerService>("@ghtokens/SecretsManagerService");

export const SecretsManagerLayer = Layer.succeed(
  SecretsManagerService,
  SecretsManagerService.of({
    getAppCredentials: (appId: string) =>
      Effect.tryPromise({
        try: async () => {
          const client = new SecretsManagerClient({});
          const response = await client.send(
            new GetSecretValueCommand({ SecretId: `/ghtokens/apps/${appId}` }),
          );
          if (!response.SecretString) {
            throw new Error("SecretString is empty");
          }
          return JSON.parse(response.SecretString) as AppCredentials;
        },
        catch: (e) =>
          new SecretsManagerError({ message: `Failed to fetch credentials for app ${appId}`, cause: e }),
      }),
  }),
);

export interface TokenResult {
  readonly token: string;
  readonly expiresAt: string;
}

export interface GitHubAppService {
  readonly getInstallationToken: (
    appId: string,
    repositories: readonly string[],
    permissions: Record<string, string>,
  ) => Effect.Effect<TokenResult, GitHubAppError | SecretsManagerError>;
  readonly listInstallationRepositories: (
    appId: string,
  ) => Effect.Effect<readonly string[], GitHubAppError | SecretsManagerError>;
}
export const GitHubAppService = Context.GenericTag<GitHubAppService>("@ghtokens/GitHubAppService");

export const GitHubAppLayer = Layer.effect(
  GitHubAppService,
  Effect.gen(function* () {
    const secretsManager = yield* SecretsManagerService;

    const credsCache = yield* Cache.make({
      capacity: 100,
      timeToLive: "1 hours",
      lookup: (appId: string) => secretsManager.getAppCredentials(appId),
    });

    const tokenCache = yield* Cache.make({
      capacity: 1000,
      timeToLive: "5 minutes",
      lookup: (key: string) =>
        Effect.gen(function* () {
          const parsed = JSON.parse(key) as {
            appId: string;
            repositories: string[];
            permissions: Record<string, string>;
          };

          const creds = yield* credsCache.get(parsed.appId);

          const octokit = new Octokit({
            authStrategy: createAppAuth,
            auth: {
              appId: creds.app_id,
              privateKey: creds.private_key,
              installationId: creds.installation_id,
            },
          });

          const response = yield* Effect.tryPromise({
            try: () =>
              octokit.request("POST /app/installations/{installation_id}/access_tokens", {
                installation_id: parseInt(creds.installation_id, 10),
                repositories: parsed.repositories,
                permissions: parsed.permissions,
              }),
            catch: (e) =>
              new GitHubAppError({ message: "Failed to generate installation token", cause: e }),
          });

          return {
            token: response.data.token,
            expiresAt: response.data.expires_at,
          } as TokenResult;
        }),
    });

    const reposCache = yield* Cache.make({
      capacity: 100,
      timeToLive: "10 minutes",
      lookup: (appId: string) =>
        Effect.gen(function* () {
          const creds = yield* credsCache.get(appId);

          const octokit = new Octokit({
            authStrategy: createAppAuth,
            auth: {
              appId: creds.app_id,
              privateKey: creds.private_key,
              installationId: creds.installation_id,
            },
          });

          // Fetch all repositories handling pagination
          let allRepos: any[] = [];
          let page = 1;
          while (true) {
            const response = yield* Effect.tryPromise({
              try: () => octokit.request("GET /installation/repositories", { per_page: 100, page }),
              catch: (e) =>
                new GitHubAppError({ message: "Failed to list installation repositories", cause: e }),
            });
            allRepos = allRepos.concat(response.data.repositories);
            if (response.data.repositories.length < 100) break;
            page++;
          }

          return allRepos.map((r: any) => r.name) as readonly string[];
        }),
    });

    return GitHubAppService.of({
      listInstallationRepositories: (appId) => reposCache.get(appId),
      getInstallationToken: (appId, repositories, permissions) => {
        const key = JSON.stringify({
          appId,
          repositories: [...repositories].sort(),
          permissions: Object.keys(permissions)
            .sort()
            .reduce((acc, k) => ({ ...acc, [k]: permissions[k] }), {}),
        });
        return tokenCache.get(key);
      },
    });
  }),
);
