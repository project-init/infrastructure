import { Context, Effect, Layer } from 'effect';
import { Schema } from '@effect/schema';
import { AuthRules } from '../models/config.js';

export class AuthorizationError extends Schema.TaggedError<AuthorizationError>()("AuthorizationError", {
  message: Schema.String,
  failedClaims: Schema.Array(Schema.Struct({
    claim: Schema.String,
    expected: Schema.Array(Schema.String),
    actual: Schema.Union(Schema.String, Schema.Undefined),
    result: Schema.Literal("denied"),
  })),
}) {}

export interface AuthRulesEngine {
  readonly evaluate: (rules: AuthRules, claims: Record<string, string>) => Effect.Effect<void, AuthorizationError>;
}

export const AuthRulesEngine = Context.GenericTag<AuthRulesEngine>("@ghtokens/AuthRulesEngine");

// Helper to convert IAM style wildcards to regex
function wildcardToRegex(pattern: string): RegExp {
  const escaped = pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&'); // Escape regex chars except * and ?
  // Convert * to .*
  const regexStr = '^' + escaped.replace(/\\\*/g, '.*') + '$';
  return new RegExp(regexStr);
}

function matchPattern(pattern: string, value: string): boolean {
  if (pattern === value) return true;
  if (pattern.includes('*')) {
    return wildcardToRegex(pattern).test(value);
  }
  return false;
}

function expandMacros(pattern: string, claims: Record<string, string>): string {
  if (pattern === '@current') {
    // repository claim has format org/repo
    return claims['repository'] || '';
  }
  return pattern;
}

export const AuthRulesEngineLayer = Layer.succeed(
  AuthRulesEngine,
  AuthRulesEngine.of({
    evaluate: (rules, claims) => Effect.gen(function* () {
      const failedClaims: Array<{
        claim: string;
        expected: string[];
        actual: string | undefined;
        result: "denied";
      }> = [];

      for (const [claim, patterns] of Object.entries(rules)) {
        const actualValue = claims[claim];
        
        if (actualValue === undefined) {
          failedClaims.push({ claim, expected: patterns, actual: undefined, result: "denied" });
          continue;
        }

        const expandedPatterns = patterns.map(p => expandMacros(p, claims));
        const negations = expandedPatterns.filter(p => p.startsWith('!')).map(p => p.slice(1));
        const positives = expandedPatterns.filter(p => !p.startsWith('!'));

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

        if (positives.length > 0) {
          let matched = false;
          for (const pos of positives) {
            if (matchPattern(pos, actualValue)) {
              matched = true;
              break;
            }
          }
          if (!matched) {
            failedClaims.push({ claim, expected: patterns, actual: actualValue, result: "denied" });
          }
        }
      }

      if (failedClaims.length > 0) {
        return yield* Effect.fail(new AuthorizationError({ 
          message: "Authorization failed", 
          failedClaims 
        }));
      }
    })
  })
);
