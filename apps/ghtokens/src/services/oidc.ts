import * as jose from 'jose';
import { Context, Effect, Layer } from 'effect';
import { Schema } from '@effect/schema';

export class JWTValidationError extends Schema.TaggedError<JWTValidationError>()("JWTValidationError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

export interface OIDCValidatorService {
  readonly validateToken: (token: string, audience?: string) => Effect.Effect<Record<string, string>, JWTValidationError>;
}

export const OIDCValidatorService = Context.GenericTag<OIDCValidatorService>("@ghtokens/OIDCValidatorService");

const JWKS_URL = "https://token.actions.githubusercontent.com/.well-known/jwks";
const ISSUER = "https://token.actions.githubusercontent.com";

// jose.createRemoteJWKSet automatically caches the keys
const JWKS = jose.createRemoteJWKSet(new URL(JWKS_URL));

export const OIDCValidatorLayer = Layer.succeed(
  OIDCValidatorService,
  OIDCValidatorService.of({
    validateToken: (token, audience = "ghtokens") => Effect.tryPromise({
      try: async () => {
        const { payload } = await jose.jwtVerify(token, JWKS, {
          issuer: ISSUER,
          audience: audience,
        });
        
        const claims: Record<string, string> = {};
        for (const [key, value] of Object.entries(payload)) {
          if (typeof value === "string") {
            claims[key] = value;
          } else if (value !== null && value !== undefined) {
            claims[key] = String(value);
          }
        }
        return claims;
      },
      catch: (e) => new JWTValidationError({ message: "Invalid or expired OIDC token", cause: e })
    })
  })
);
