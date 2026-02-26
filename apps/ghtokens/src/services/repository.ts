import { Context, Effect, Layer } from "effect";
import { DynamoDBClient, GetItemCommand, PutItemCommand, DeleteItemCommand, QueryCommand, ScanCommand } from "@aws-sdk/client-dynamodb";
import { marshall, unmarshall } from "@aws-sdk/util-dynamodb";
import { TokenConfiguration, AuditRecord } from "../models/config.js";
import { Schema } from "@effect/schema";

export class DynamoDBError extends Schema.TaggedError<DynamoDBError>()("DynamoDBError", {
  message: Schema.String,
  cause: Schema.Unknown,
}) {}

export class ConfigNotFoundError extends Schema.TaggedError<ConfigNotFoundError>()("ConfigNotFoundError", {
  namespace: Schema.String,
  name: Schema.String,
}) {}

export interface RepositoryService {
  readonly getConfig: (namespace: string, name: string) => Effect.Effect<TokenConfiguration, DynamoDBError | ConfigNotFoundError>;
  readonly createConfig: (config: TokenConfiguration) => Effect.Effect<void, DynamoDBError>;
  readonly updateConfig: (config: TokenConfiguration) => Effect.Effect<void, DynamoDBError>;
  readonly deleteConfig: (namespace: string, name: string) => Effect.Effect<void, DynamoDBError>;
  readonly listConfigs: (namespace?: string) => Effect.Effect<TokenConfiguration[], DynamoDBError>;
  readonly appendAuditLog: (record: AuditRecord) => Effect.Effect<void, DynamoDBError>;
}

export const RepositoryService = Context.GenericTag<RepositoryService>("@ghtokens/RepositoryService");

export const makeRepositoryService = (client: DynamoDBClient, tableName: string): RepositoryService => {
  return {
    getConfig: (namespace, name) => Effect.tryPromise({
      try: async () => {
        const result = await client.send(new GetItemCommand({
          TableName: tableName,
          Key: marshall({
            pk: `CFG#${namespace}`,
            sk: name
          })
        }));
        if (!result.Item) {
          throw new ConfigNotFoundError({ namespace, name });
        }
        return unmarshall(result.Item) as TokenConfiguration;
      },
      catch: (e) => {
        if (e instanceof ConfigNotFoundError) return e;
        return new DynamoDBError({ message: "Failed to get config", cause: e });
      }
    }).pipe(
      Effect.catchIf((e) => e instanceof ConfigNotFoundError, Effect.fail)
    ),

    createConfig: (config) => Effect.tryPromise({
      try: async () => {
        await client.send(new PutItemCommand({
          TableName: tableName,
          Item: marshall({
            ...config,
            pk: `CFG#${config.namespace}`,
            sk: config.name
          }),
          ConditionExpression: "attribute_not_exists(pk)"
        }));
      },
      catch: (e) => new DynamoDBError({ message: "Failed to create config", cause: e })
    }),

    updateConfig: (config) => Effect.tryPromise({
      try: async () => {
        await client.send(new PutItemCommand({
          TableName: tableName,
          Item: marshall({
            ...config,
            pk: `CFG#${config.namespace}`,
            sk: config.name
          }),
          ConditionExpression: "attribute_exists(pk)"
        }));
      },
      catch: (e) => new DynamoDBError({ message: "Failed to update config", cause: e })
    }),

    deleteConfig: (namespace, name) => Effect.tryPromise({
      try: async () => {
        await client.send(new DeleteItemCommand({
          TableName: tableName,
          Key: marshall({
            pk: `CFG#${namespace}`,
            sk: name
          })
        }));
      },
      catch: (e) => new DynamoDBError({ message: "Failed to delete config", cause: e })
    }),

    listConfigs: (namespace) => Effect.tryPromise({
      try: async () => {
        if (namespace) {
          const result = await client.send(new QueryCommand({
            TableName: tableName,
            KeyConditionExpression: "pk = :pk",
            ExpressionAttributeValues: marshall({
              ":pk": `CFG#${namespace}`
            })
          }));
          return (result.Items || []).map(item => unmarshall(item) as TokenConfiguration);
        } else {
          // Scan for all configs - in production we'd want pagination
          const result = await client.send(new ScanCommand({
            TableName: tableName,
            FilterExpression: "begins_with(pk, :prefix)",
            ExpressionAttributeValues: marshall({
              ":prefix": "CFG#"
            })
          }));
          return (result.Items || []).map(item => unmarshall(item) as TokenConfiguration);
        }
      },
      catch: (e) => new DynamoDBError({ message: "Failed to list configs", cause: e })
    }),

    appendAuditLog: (record) => Effect.tryPromise({
      try: async () => {
        await client.send(new PutItemCommand({
          TableName: tableName,
          Item: marshall(record, { removeUndefinedValues: true })
        }));
      },
      catch: (e) => new DynamoDBError({ message: "Failed to append audit log", cause: e })
    })
  };
};

export const RepositoryLayer = (tableName: string) => Layer.effect(
  RepositoryService,
  Effect.gen(function* () {
    const client = new DynamoDBClient({});
    return makeRepositoryService(client, tableName);
  })
);
