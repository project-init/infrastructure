import { Context, Effect, Layer } from "effect";
import { DynamoDBClient, GetItemCommand, PutItemCommand, DeleteItemCommand, QueryCommand, ScanCommand } from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";
import type { TokenConfiguration, AuditRecord } from "../models/config.js";
import { DynamoDBError, ConfigNotFoundError } from "./errors.js";

export interface RepositoryService {
  readonly getConfig: (namespace: string, name: string) => Effect.Effect<TokenConfiguration, DynamoDBError | ConfigNotFoundError>;
  readonly createConfig: (config: TokenConfiguration) => Effect.Effect<void, DynamoDBError>;
  readonly updateConfig: (config: TokenConfiguration) => Effect.Effect<void, DynamoDBError>;
  readonly deleteConfig: (namespace: string, name: string) => Effect.Effect<void, DynamoDBError>;
  readonly listConfigs: (namespace?: string) => Effect.Effect<TokenConfiguration[], DynamoDBError>;
  readonly appendAuditLog: (record: AuditRecord) => Effect.Effect<void, DynamoDBError>;
}

export const RepositoryService = Context.GenericTag<RepositoryService>("@ghtokens/RepositoryService");

export const makeRepositoryService = (client: DynamoDBClient, tableName: string): RepositoryService => ({
  getConfig: (namespace, name) =>
    Effect.tryPromise({
      try: async () => {
        const result = await client.send(new GetItemCommand({
          TableName: tableName,
          Key: marshall({ pk: `CFG#${namespace}`, sk: name }),
        }));
        if (!result.Item) {
          throw { _tag: "not_found" as const, namespace, name };
        }
        return unmarshall(result.Item) as TokenConfiguration;
      },
      catch: (e) => {
        if (typeof e === "object" && e !== null && "_tag" in e && (e as { _tag: string })._tag === "not_found") {
          const err = e as unknown as { namespace: string; name: string };
          return new ConfigNotFoundError({ namespace: err.namespace, name: err.name });
        }
        return new DynamoDBError({ message: "Failed to get config", cause: e });
      },
    }),

  createConfig: (config) =>
    Effect.tryPromise({
      try: () => client.send(new PutItemCommand({
        TableName: tableName,
        Item: marshall({ ...config, pk: `CFG#${config.namespace}`, sk: config.name }),
        ConditionExpression: "attribute_not_exists(pk)",
      })).then(() => undefined),
      catch: (e) => new DynamoDBError({ message: "Failed to create config", cause: e }),
    }),

  updateConfig: (config) =>
    Effect.tryPromise({
      try: () => client.send(new PutItemCommand({
        TableName: tableName,
        Item: marshall({ ...config, pk: `CFG#${config.namespace}`, sk: config.name }),
        ConditionExpression: "attribute_exists(pk)",
      })).then(() => undefined),
      catch: (e) => new DynamoDBError({ message: "Failed to update config", cause: e }),
    }),

  deleteConfig: (namespace, name) =>
    Effect.tryPromise({
      try: () => client.send(new DeleteItemCommand({
        TableName: tableName,
        Key: marshall({ pk: `CFG#${namespace}`, sk: name }),
      })).then(() => undefined),
      catch: (e) => new DynamoDBError({ message: "Failed to delete config", cause: e }),
    }),

  listConfigs: (namespace) =>
    Effect.tryPromise({
      try: async () => {
        if (namespace) {
          const result = await client.send(new QueryCommand({
            TableName: tableName,
            KeyConditionExpression: "pk = :pk",
            ExpressionAttributeValues: marshall({ ":pk": `CFG#${namespace}` }),
          }));
          return (result.Items ?? []).map((item) => unmarshall(item) as TokenConfiguration);
        }
        const result = await client.send(new ScanCommand({
          TableName: tableName,
          FilterExpression: "begins_with(pk, :prefix)",
          ExpressionAttributeValues: marshall({ ":prefix": "CFG#" }),
        }));
        return (result.Items ?? []).map((item) => unmarshall(item) as TokenConfiguration);
      },
      catch: (e) => new DynamoDBError({ message: "Failed to list configs", cause: e }),
    }),

  appendAuditLog: (record) =>
    Effect.tryPromise({
      try: () => client.send(new PutItemCommand({
        TableName: tableName,
        Item: marshall(record, { removeUndefinedValues: true }),
      })).then(() => undefined),
      catch: (e) => new DynamoDBError({ message: "Failed to append audit log", cause: e }),
    }),
});

export const RepositoryLayer = (tableName: string) =>
  Layer.succeed(RepositoryService, makeRepositoryService(new DynamoDBClient({}), tableName));
