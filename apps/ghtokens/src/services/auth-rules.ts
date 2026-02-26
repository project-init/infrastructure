import { Context, Effect, Layer } from "effect";
import type { AuthRules } from "../models/config.js";
import { AuthorizationError } from "./errors.js";

export interface AuthRulesEngine {
  readonly evaluate: (rules: AuthRules, claims: Record<string, string>) => Effect.Effect<void, AuthorizationError>;
}

export const AuthRulesEngine = Context.GenericTag<AuthRulesEngine>("@ghtokens/AuthRulesEngine");

/** Convert IAM-style wildcard patterns to regex */
function wildcardToRegex(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  const regexStr = "^" + escaped.replace(/\*/g, ".*") + "$";
  return new RegExp(regexStr);
}

function matchPattern(pattern: string, value: string): boolean {
  if (pattern === value) return true;
  if (pattern.includes("*")) {
    return wildcardToRegex(pattern).test(value);
  }
  return false;
}

function expandMacros(pattern: string, claims: Record<string, string>): string {
  if (pattern === "@current") {
    return claims["repository"] ?? "";
  }
  return pattern;
}

export const AuthRulesEngineLayer = Layer.succeed(
  AuthRulesEngine,
  AuthRulesEngine.of({
    evaluate: (rules, claims) =>
      Effect.gen(function* () {
        const failedClaims: Array<{
          claim: string;
          expected: readonly string[];
          actual: string | undefined;
          result: "denied";
        }> = [];

        for (const [claim, patterns] of Object.entries(rules)) {
          const actualValue = claims[claim];

          // Configured claim missing from token -> fail
          if (actualValue === undefined) {
            failedClaims.push({ claim, expected: patterns, actual: undefined, result: "denied" });
            continue;
          }

          const expandedPatterns = patterns.map((p) => expandMacros(p, claims));
          const negations = expandedPatterns.filter((p) => p.startsWith("!")).map((p) => p.slice(1));
          const positives = expandedPatterns.filter((p) => !p.startsWith("!"));

          // Negation check first
          let blocked = false;
          for (const neg of negations) {
            if (matchPattern(neg, actualValue)) {
              blocked = true;
              break;
            }
          }
          if (blocked) {
            failedClaims.push({ claim, expected: patterns, actual: actualValue, result: "denied" });
            continue;
          }

          // Positive pattern check
          if (positives.length > 0) {
            const matched = positives.some((pos) => matchPattern(pos, actualValue));
            if (!matched) {
              failedClaims.push({ claim, expected: patterns, actual: actualValue, result: "denied" });
            }
          }
        }

        if (failedClaims.length > 0) {
          return yield* Effect.fail(
            new AuthorizationError({ message: "Authorization failed", failedClaims }),
          );
        }
      }),
  }),
);
