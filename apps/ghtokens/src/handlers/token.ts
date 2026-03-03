import type { ConnectRouter } from "@connectrpc/connect";
import { ConnectError, Code } from "@connectrpc/connect";
import { timestampFromDate } from "@bufbuild/protobuf/wkt";
import { Effect } from "effect";
import { TokenService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/token_pb";
import type { GetTokenRequest, GetTokenResponse, DryRunRequest, DryRunResponse } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/token_pb";
import { appRuntime } from "../runtime.js";
import { mapErrorToConnect, extractBearerToken } from "./errors.js";
import { GitHubAppError } from "../services/errors.js";
import { RepositoryService } from "../services/repository.js";
import { OIDCValidatorService } from "../services/oidc.js";
import { AuthRulesEngine } from "../services/auth-rules.js";
import { GitHubAppService } from "../services/github.js";

export const registerTokenHandlers = (router: ConnectRouter) => {
  router.service(TokenService, {
    getToken: async (req: GetTokenRequest, ctx) => {
      const bearerToken = extractBearerToken(ctx);
      if (!bearerToken) {
        throw new ConnectError("Missing or invalid Authorization header", Code.Unauthenticated);
      }

      const program = Effect.gen(function*() {
        const repo = yield* RepositoryService;
        const oidc = yield* OIDCValidatorService;
        const authEngine = yield* AuthRulesEngine;
        const github = yield* GitHubAppService;

        // 1. Validate OIDC token and extract claims
        const claims = yield* oidc.validateToken(bearerToken);

        // 2. Look up token configuration
        const config = yield* repo.getConfig(req.namespace, req.name);

        // 3. Evaluate auth rules against claims
        yield* authEngine.evaluate(config.auth, claims).pipe(
          Effect.catchTag("AuthorizationError", (e) =>
            Effect.gen(function*() {
              yield* repo.appendAuditLog({
                pk: `AUDIT#${req.namespace}#${req.name}`,
                sk: `${new Date().toISOString()}#${crypto.randomUUID()}`,
                event_type: "TOKEN_DENIED",
                actor: claims["actor"] ?? "unknown",
                timestamp: new Date().toISOString(),
                oidc_claims: claims,
                failed_rules: e.failedClaims.map((c) => c.claim),
              }).pipe(Effect.ignore);
              return yield* Effect.fail(e);
            }),
          ),
        );

        // 4. Resolve repositories (expand @current macro)
        let resolvedRepos = config.repositories
          .map((r) => {
            if (r === "@current" && claims["repository"]) {
              const parts = claims["repository"].split("/");
              return parts.length > 1 ? parts[1]! : claims["repository"];
            }
            return r;
          })
          .filter((r): r is string => r !== undefined);

        // 5. Determine GitHub App ID
        const appId = config.github_app_id ?? process.env.DEFAULT_GITHUB_APP_ID;
        if (!appId) {
          return yield* Effect.fail(new GitHubAppError({ message: "No GitHub App ID configured", cause: null }));
        }

        // 6. Expand wildcards in repositories
        if (resolvedRepos.some((r) => r.includes("*"))) {
          const availableRepos = yield* github.listInstallationRepositories(appId);
          const expandedRepos = new Set<string>();

          for (const pattern of resolvedRepos) {
            if (pattern.includes("*")) {
              const regexStr = "^" + pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*") + "$";
              const regex = new RegExp(regexStr);
              for (const repo of availableRepos) {
                if (regex.test(repo)) {
                  expandedRepos.add(repo);
                }
              }
            } else {
              expandedRepos.add(pattern);
            }
          }
          resolvedRepos = Array.from(expandedRepos);
        }

        // 7. Request installation token
        const tokenResult = yield* github.getInstallationToken(
          appId,
          resolvedRepos,
          config.permissions,
        );

        // 8. Log audit event
        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${new Date().toISOString()}#${crypto.randomUUID()}`,
          event_type: "TOKEN_REQUEST",
          actor: claims["actor"] ?? "unknown",
          timestamp: new Date().toISOString(),
          oidc_claims: claims,
        });

        return {
          token: tokenResult.token,
          expiresAt: timestampFromDate(new Date(tokenResult.expiresAt)),
          repositories: resolvedRepos,
          permissions: config.permissions,
        } satisfies Partial<GetTokenResponse>;
      });

      const result = await appRuntime.runPromise(Effect.either(program));
      if (result._tag === "Left") throw mapErrorToConnect(result.left);
      return result.right;
    },

    dryRun: async (req: DryRunRequest, ctx) => {
      const bearerToken = extractBearerToken(ctx);
      if (!bearerToken) {
        throw new ConnectError("Missing or invalid Authorization header", Code.Unauthenticated);
      }

      const program = Effect.gen(function*() {
        const repo = yield* RepositoryService;
        const oidc = yield* OIDCValidatorService;
        const authEngine = yield* AuthRulesEngine;

        const claims = yield* oidc.validateToken(bearerToken);
        const config = yield* repo.getConfig(req.namespace, req.name);

        const authResult = yield* Effect.either(authEngine.evaluate(config.auth, claims));

        // Audit log the dry run
        yield* repo
          .appendAuditLog({
            pk: `AUDIT#${req.namespace}#${req.name}`,
            sk: `${new Date().toISOString()}#${crypto.randomUUID()}`,
            event_type: authResult._tag === "Right" ? "TOKEN_REQUEST" : "TOKEN_DENIED",
            actor: claims["actor"] ?? "unknown",
            timestamp: new Date().toISOString(),
            oidc_claims: claims,
          })
          .pipe(Effect.ignore);

        if (authResult._tag === "Right") {
          return {
            authorized: true,
            matchedClaims: Object.keys(config.auth),
            failedClaims: [] as string[],
          } satisfies Partial<DryRunResponse>;
        }

        const failedClaimNames = new Set(authResult.left.failedClaims.map((c) => c.claim));
        const matchedClaims = Object.keys(config.auth).filter((c) => !failedClaimNames.has(c));

        return {
          authorized: false,
          matchedClaims,
          failedClaims: authResult.left.failedClaims.map(
            (c) => `${c.claim}: expected [${c.expected.join(", ")}], actual ${c.actual}`,
          ),
        } satisfies Partial<DryRunResponse>;
      });

      const result = await appRuntime.runPromise(Effect.either(program));
      if (result._tag === "Left") throw mapErrorToConnect(result.left);
      return result.right;
    },
  });
};
