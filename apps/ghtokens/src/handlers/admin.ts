import type { ConnectRouter } from "@connectrpc/connect";
import { create } from "@bufbuild/protobuf";
import { timestampFromDate } from "@bufbuild/protobuf/wkt";
import { Effect } from "effect";
import { AdminService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/admin_pb";
import type {
  CreateConfigurationRequest,
  GetConfigurationRequest,
  UpdateConfigurationRequest,
  DeleteConfigurationRequest,
  ListConfigurationsRequest,
} from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/admin_pb";
import { TokenConfigurationSchema } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/common_pb";
import { appRuntime } from "../runtime.js";
import { mapErrorToConnect } from "./errors.js";
import { RepositoryService } from "../services/repository.js";

/**
 * Convert a protobuf AuthRules message to our internal AuthRules format.
 * The proto has named fields (actor, repository, ref, etc.), but our internal
 * format is a Record<string, string[]>.
 */
function protoAuthRulesToInternal(auth: {
  actor: string[];
  repository: string[];
  jobWorkflowRef: string[];
  ref: string[];
  eventName: string[];
  environment: string[];
} | undefined): Record<string, string[]> {
  if (!auth) return {};
  const rules: Record<string, string[]> = {};
  if (auth.actor.length > 0) rules["actor"] = [...auth.actor];
  if (auth.repository.length > 0) rules["repository"] = [...auth.repository];
  if (auth.jobWorkflowRef.length > 0) rules["job_workflow_ref"] = [...auth.jobWorkflowRef];
  if (auth.ref.length > 0) rules["ref"] = [...auth.ref];
  if (auth.eventName.length > 0) rules["event_name"] = [...auth.eventName];
  if (auth.environment.length > 0) rules["environment"] = [...auth.environment];
  return rules;
}

function domainConfigToProto(config: {
  namespace: string;
  name: string;
  description: string;
  github_app_id?: string;
  auth: Record<string, readonly string[]>;
  repositories: readonly string[];
  permissions: Record<string, string>;
  created_at: string;
  updated_at: string;
  created_by: string;
  updated_by: string;
}) {
  return create(TokenConfigurationSchema, {
    namespace: config.namespace,
    name: config.name,
    description: config.description,
    githubAppId: config.github_app_id,
    auth: {
      actor: [...(config.auth["actor"] ?? [])],
      repository: [...(config.auth["repository"] ?? [])],
      jobWorkflowRef: [...(config.auth["job_workflow_ref"] ?? [])],
      ref: [...(config.auth["ref"] ?? [])],
      eventName: [...(config.auth["event_name"] ?? [])],
      environment: [...(config.auth["environment"] ?? [])],
    },
    repositories: [...config.repositories],
    permissions: { permissions: { ...config.permissions } },
    createdAt: timestampFromDate(new Date(config.created_at)),
    updatedAt: timestampFromDate(new Date(config.updated_at)),
    createdBy: config.created_by,
    updatedBy: config.updated_by,
  });
}

export const registerAdminHandlers = (router: ConnectRouter) => {
  router.service(AdminService, {
    createConfiguration: async (req: CreateConfigurationRequest) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const now = new Date().toISOString();
        const proto = req.configuration;

        const config = {
          namespace: proto?.namespace ?? "",
          name: proto?.name ?? "",
          description: proto?.description ?? "",
          github_app_id: proto?.githubAppId,
          auth: protoAuthRulesToInternal(proto?.auth),
          repositories: proto?.repositories ?? [],
          permissions: proto?.permissions?.permissions ?? {},
          created_at: now,
          updated_at: now,
          created_by: "admin",
          updated_by: "admin",
        };

        yield* repo.createConfig(config);

        yield* repo.appendAuditLog({
          pk: `AUDIT#${config.namespace}#${config.name}`,
          sk: `${now}#${crypto.randomUUID()}`,
          event_type: "CREATE",
          actor: "admin",
          timestamp: now,
          new_value: config,
        });

        return { configuration: domainConfigToProto(config) };
      }).pipe(Effect.catchAll((e) => Effect.fail(mapErrorToConnect(e))));

      return appRuntime.runPromise(program);
    },

    getConfiguration: async (req: GetConfigurationRequest) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const config = yield* repo.getConfig(req.namespace, req.name);
        return { configuration: domainConfigToProto(config) };
      }).pipe(Effect.catchAll((e) => Effect.fail(mapErrorToConnect(e))));

      return appRuntime.runPromise(program);
    },

    updateConfiguration: async (req: UpdateConfigurationRequest) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const now = new Date().toISOString();
        const proto = req.configuration;

        const previousConfig = yield* repo.getConfig(req.namespace, req.name);

        const newConfig = {
          ...previousConfig,
          description: proto?.description ?? previousConfig.description,
          github_app_id: proto?.githubAppId ?? previousConfig.github_app_id,
          auth: proto?.auth ? protoAuthRulesToInternal(proto.auth) : previousConfig.auth,
          repositories: proto?.repositories ?? previousConfig.repositories,
          permissions: proto?.permissions?.permissions ?? previousConfig.permissions,
          updated_at: now,
          updated_by: "admin",
        };

        yield* repo.updateConfig(newConfig);

        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${now}#${crypto.randomUUID()}`,
          event_type: "UPDATE",
          actor: "admin",
          timestamp: now,
          previous_value: previousConfig,
          new_value: newConfig,
        });

        return { configuration: domainConfigToProto(newConfig) };
      }).pipe(Effect.catchAll((e) => Effect.fail(mapErrorToConnect(e))));

      return appRuntime.runPromise(program);
    },

    deleteConfiguration: async (req: DeleteConfigurationRequest) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const now = new Date().toISOString();

        const previousConfig = yield* repo.getConfig(req.namespace, req.name);
        yield* repo.deleteConfig(req.namespace, req.name);

        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${now}#${crypto.randomUUID()}`,
          event_type: "DELETE",
          actor: "admin",
          timestamp: now,
          previous_value: previousConfig,
        });

        return {};
      }).pipe(Effect.catchAll((e) => Effect.fail(mapErrorToConnect(e))));

      return appRuntime.runPromise(program);
    },

    listConfigurations: async (req: ListConfigurationsRequest) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const configs = yield* repo.listConfigs(req.namespace || undefined);

        return {
          configurations: configs.map((c) => domainConfigToProto(c)),
        };
      }).pipe(Effect.catchAll((e) => Effect.fail(mapErrorToConnect(e))));

      return appRuntime.runPromise(program);
    },
  });
};
