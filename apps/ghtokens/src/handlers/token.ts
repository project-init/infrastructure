import type { ConnectRouter } from "@connectrpc/connect";
import { TokenService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/token_connect";
import { appRuntime } from "../runtime.js";
import { mapErrorToConnect, extractBearerToken } from "./errors.js";
import { Effect } from "effect";
import { RepositoryService } from "../services/repository.js";
import { OIDCValidatorService } from "../services/oidc.js";
import { AuthRulesEngine } from "../services/auth-rules.js";
import { GitHubAppService } from "../services/github.js";
import { ConnectError, Code } from "@connectrpc/connect";
import { Timestamp } from "@bufbuild/protobuf";
import type { GetTokenRequest, DryRunRequest } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/token_pb";

export const registerTokenHandlers = (router: ConnectRouter) => {
  router.service(TokenService, {
    getToken: async (req, ctx) => {
      const token = extractBearerToken(ctx);
      if (!token) {
        throw new ConnectError("Missing or invalid Authorization header", Code.Unauthenticated);
      }

      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const oidc = yield* OIDCValidatorService;
        const auth = yield* AuthRulesEngine;
        const github = yield* GitHubAppService;

        // 1. Validate OIDC token and extract claims
        const claims = yield* oidc.validateToken(token);

        // 2. Look up token configuration
        const config = yield* repo.getConfig(req.namespace, req.name);

        // 3. Evaluate auth rules
        yield* auth.evaluate(config.auth, claims);

        // 4. Resolve repositories (expand @current macro)
        const resolvedRepos = config.repositories.map(repo => {
          if (repo === '@current' && claims['repository']) {
            const parts = claims['repository'].split('/');
            return parts.length > 1 ? parts[1] : claims['repository'];
          }
          return repo;
        }).filter((repo): repo is string => repo !== undefined);

        // 5. Determine GitHub App ID
        const appId = config.github_app_id || process.env.DEFAULT_GITHUB_APP_ID;
        if (!appId) {
          throw new Error("No GitHub App ID configured");
        }

        // 6. Request installation token
        const tokenResult = yield* github.getInstallationToken(
          appId, 
          resolvedRepos, 
          config.permissions
        );

        // 7. Log audit event
        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${new Date().toISOString()}#${crypto.randomUUID()}`,
          event_type: "TOKEN_REQUEST",
          actor: claims['actor'] || 'unknown',
          timestamp: new Date().toISOString(),
          oidc_claims: claims,
        });

        return {
          token: tokenResult.token,
          expiresAt: Timestamp.fromDate(new Date(tokenResult.expiresAt)),
          repositories: resolvedRepos,
          permissions: config.permissions,
        };
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    },

    dryRun: async (req, ctx) => {
      const token = extractBearerToken(ctx);
      if (!token) {
        throw new ConnectError("Missing or invalid Authorization header", Code.Unauthenticated);
      }

      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const oidc = yield* OIDCValidatorService;
        const auth = yield* AuthRulesEngine;

        const claims = yield* oidc.validateToken(token);
        const config = yield* repo.getConfig(req.namespace, req.name);

        const authResult = yield* Effect.either(auth.evaluate(config.auth, claims));

        // Audit log the dry run
        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${new Date().toISOString()}#${crypto.randomUUID()}`,
          event_type: authResult._tag === "Right" ? "TOKEN_REQUEST" : "TOKEN_DENIED",
          actor: claims['actor'] || 'unknown',
          timestamp: new Date().toISOString(),
          oidc_claims: claims,
        }).pipe(Effect.ignore); // Ignore audit log failures for dry runs

        if (authResult._tag === "Right") {
          return {
            authorized: true,
            matchedClaims: Object.keys(config.auth), // Simplified for now
            failedClaims: [],
          };
        } else {
          return {
            authorized: false,
            matchedClaims: [], // Simplified for now
            failedClaims: authResult.left.failedClaims.map(c => 
              `${c.claim}: expected [${c.expected.join(', ')}], actual ${c.actual}`
            ),
          };
        }
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    }
  });
};
