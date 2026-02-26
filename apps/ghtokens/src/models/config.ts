import { Schema as S } from "@effect/schema";

export const AuthRules = S.Record({
  key: S.String,
  value: S.Array(S.String)
});
export type AuthRules = S.Schema.Type<typeof AuthRules>;

export const Permissions = S.Record({
  key: S.String,
  value: S.String
});
export type Permissions = S.Schema.Type<typeof Permissions>;

export const TokenConfiguration = S.Struct({
  namespace: S.String,
  name: S.String,
  description: S.String,
  github_app_id: S.optionalWith(S.String, { exact: true }),
  auth: AuthRules,
  repositories: S.Array(S.String),
  permissions: Permissions,
  created_at: S.String,
  updated_at: S.String,
  created_by: S.String,
  updated_by: S.String,
});

export type TokenConfiguration = S.Schema.Type<typeof TokenConfiguration>;

export const AuditEventType = S.Literal("CREATE", "UPDATE", "DELETE", "TOKEN_REQUEST", "TOKEN_DENIED");
export type AuditEventType = S.Schema.Type<typeof AuditEventType>;

export const AuditRecord = S.Struct({
  pk: S.String,
  sk: S.String,
  event_type: AuditEventType,
  actor: S.String,
  timestamp: S.String,
  previous_value: S.optionalWith(TokenConfiguration, { exact: true }),
  new_value: S.optionalWith(TokenConfiguration, { exact: true }),
  oidc_claims: S.optionalWith(S.Record({ key: S.String, value: S.String }), { exact: true }),
  matched_rules: S.optionalWith(S.Array(S.String), { exact: true }),
  failed_rules: S.optionalWith(S.Array(S.String), { exact: true }),
});

export type AuditRecord = S.Schema.Type<typeof AuditRecord>;
