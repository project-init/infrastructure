/**
 * Internal domain types for the ghtokens service.
 * These are used for DynamoDB persistence and internal logic,
 * separate from the protobuf-generated types used at the API boundary.
 */

export interface AuthRules {
  readonly [claim: string]: readonly string[];
}

export interface Permissions {
  readonly [permission: string]: string;
}

export interface TokenConfiguration {
  readonly namespace: string;
  readonly name: string;
  readonly description: string;
  readonly github_app_id?: string;
  readonly auth: AuthRules;
  readonly repositories: readonly string[];
  readonly permissions: Permissions;
  readonly created_at: string;
  readonly updated_at: string;
  readonly created_by: string;
  readonly updated_by: string;
}

export type AuditEventType = "CREATE" | "UPDATE" | "DELETE" | "TOKEN_REQUEST" | "TOKEN_DENIED";

export interface AuditRecord {
  readonly pk: string;
  readonly sk: string;
  readonly event_type: AuditEventType;
  readonly actor: string;
  readonly timestamp: string;
  readonly previous_value?: TokenConfiguration;
  readonly new_value?: TokenConfiguration;
  readonly oidc_claims?: Record<string, string>;
  readonly matched_rules?: readonly string[];
  readonly failed_rules?: readonly string[];
}
