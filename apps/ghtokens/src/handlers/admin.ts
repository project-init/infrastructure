import { ConnectRouter } from "@connectrpc/connect";
import { AdminService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/admin_connect";
import { appRuntime } from "../runtime.js";
import { mapErrorToConnect } from "./errors.js";
import { Effect } from "effect";
import { RepositoryService } from "../services/repository.js";
import { Timestamp } from "@bufbuild/protobuf";

export const registerAdminHandlers = (router: ConnectRouter) => {
  router.service(AdminService, {
    createConfiguration: async (req) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const now = new Date().toISOString();
        
        const config = {
          namespace: req.namespace,
          name: req.name,
          description: req.description,
          github_app_id: req.githubAppId,
          auth: req.auth,
          repositories: req.repositories,
          permissions: req.permissions,
          created_at: now,
          updated_at: now,
          created_by: "admin", // Would come from IAM caller context in AWS
          updated_by: "admin",
        };

        yield* repo.createConfig(config);

        yield* repo.appendAuditLog({
          pk: `AUDIT#${req.namespace}#${req.name}`,
          sk: `${now}#${crypto.randomUUID()}`,
          event_type: "CREATE",
          actor: "admin",
          timestamp: now,
          new_value: config,
        });

        return {};
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    },

    getConfiguration: async (req) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const config = yield* repo.getConfig(req.namespace, req.name);

        return {
          namespace: config.namespace,
          name: config.name,
          description: config.description,
          githubAppId: config.github_app_id,
          auth: config.auth,
          repositories: config.repositories,
          permissions: config.permissions,
          createdAt: Timestamp.fromDate(new Date(config.created_at)),
          updatedAt: Timestamp.fromDate(new Date(config.updated_at)),
        };
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    },

    updateConfiguration: async (req) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const now = new Date().toISOString();

        const previousConfig = yield* repo.getConfig(req.namespace, req.name);

        const newConfig = {
          ...previousConfig,
          description: req.description,
          github_app_id: req.githubAppId,
          auth: req.auth,
          repositories: req.repositories,
          permissions: req.permissions,
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

        return {};
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    },

    deleteConfiguration: async (req) => {
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
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    },

    listConfigurations: async (req) => {
      const program = Effect.gen(function* () {
        const repo = yield* RepositoryService;
        const configs = yield* repo.listConfigs(req.namespace || undefined);

        return {
          configurations: configs.map(c => ({
            namespace: c.namespace,
            name: c.name,
            description: c.description,
            githubAppId: c.github_app_id,
            auth: c.auth,
            repositories: c.repositories,
            permissions: c.permissions,
            createdAt: Timestamp.fromDate(new Date(c.created_at)),
            updatedAt: Timestamp.fromDate(new Date(c.updated_at)),
          }))
        };
      }).pipe(
        Effect.catchAll(e => Effect.fail(mapErrorToConnect(e)))
      );

      return appRuntime.runPromise(program);
    }
  });
};
