import { describe, it, expect } from "bun:test";
import { createClient } from "@connectrpc/connect";
import { createConnectTransport } from "@connectrpc/connect-node";
import { AdminService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/admin_pb";
import { TokenService } from "@project-init/ghtokens-proto/src/gen/ghtokens/v1/token_pb";
import { ConnectError, Code } from "@connectrpc/connect";

const transport = createConnectTransport({
  baseUrl: process.env.API_BASE_URL || "http://127.0.0.1:8080",
  httpVersion: "1.1",
});

const adminClient = createClient(AdminService, transport);
const tokenClient = createClient(TokenService, transport);

const iamHeaders = {
  Authorization: process.env.AWS_AUTH_HEADER || "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20260302/us-east-1/execute-api/aws4_request",
  "x-amzn-iam-principal": process.env.AWS_IAM_PRINCIPAL || "arn:aws:iam::123456789012:user/admin",
};

describe("GitHub Tokens API Integration Tests", () => {
  const namespace = "integration-test";
  const name = `test-config-${Date.now()}`;
  const isSmokeTest = process.env.SMOKE_TEST === "true";

  describe("Read-Only Operations (Smoke Tests)", () => {
    describe("AdminService", () => {
      it("should list configurations", async () => {
        const response = await adminClient.listConfigurations(
          { namespace },
          { headers: iamHeaders }
        );

        expect(response.configurations).toBeDefined();
        expect(Array.isArray(response.configurations)).toBe(true);
      });

      it("should get an existing configuration if any exist", async () => {
        const listResponse = await adminClient.listConfigurations(
          { namespace },
          { headers: iamHeaders }
        );

        if (listResponse.configurations.length > 0) {
          const config = listResponse.configurations[0];
          if (!config) return;
          const response = await adminClient.getConfiguration(
            { namespace: config.namespace, name: config.name },
            { headers: iamHeaders }
          );

          expect(response.configuration).toBeDefined();
          expect(response.configuration?.namespace).toBe(config.namespace);
          expect(response.configuration?.name).toBe(config.name);
        }
      });

      it("should fail without IAM authentication headers", async () => {
        try {
          await adminClient.listConfigurations({ namespace });
          expect().fail("Expected request to fail without IAM headers");
        } catch (e) {
          expect(e).toBeInstanceOf(ConnectError);
          expect((e as ConnectError).code).toBe(Code.Unauthenticated);
        }
      });
    });

    describe("TokenService", () => {
      it("should reject getToken without Bearer token", async () => {
        try {
          await tokenClient.getToken({
            namespace: "test-ns",
            name: "test-name",
          });
          expect().fail("Expected request to fail without Bearer token");
        } catch (e) {
          expect(e).toBeInstanceOf(ConnectError);
          expect((e as ConnectError).code).toBe(Code.Unauthenticated);
        }
      });

      it("should reject dryRun with invalid Bearer token", async () => {
        try {
          await tokenClient.dryRun(
            {
              namespace: "test-ns",
              name: "test-name",
            },
            { headers: { Authorization: "Bearer invalid.token.here" } }
          );
          expect().fail("Expected request to fail with invalid Bearer token");
        } catch (e) {
          expect(e).toBeInstanceOf(ConnectError);
          expect((e as ConnectError).code).toBe(Code.Unauthenticated);
        }
      });
    });
  });

  describe.skipIf(isSmokeTest)("Mutative Operations", () => {
    describe("AdminService", () => {
      it("should create a new configuration", async () => {
        const response = await adminClient.createConfiguration(
          {
            configuration: {
              namespace,
              name,
              description: "Test configuration",
              githubAppId: "test-app-id",
              auth: {
                actor: ["test-user"],
                repository: ["project-init/*"],
                jobWorkflowRef: [],
                ref: [],
                eventName: [],
                environment: [],
              },
              repositories: ["project-init/test-repo"],
              permissions: {
                permissions: {
                  contents: "read",
                },
              },
            },
          },
          { headers: iamHeaders }
        );

        expect(response.configuration).toBeDefined();
        expect(response.configuration?.namespace).toBe(namespace);
        expect(response.configuration?.name).toBe(name);
        expect(response.configuration?.description).toBe("Test configuration");
        expect(response.configuration?.githubAppId).toBe("test-app-id");
        expect(response.configuration?.repositories).toEqual(["project-init/test-repo"]);
      });

      it("should get the newly created configuration", async () => {
        const response = await adminClient.getConfiguration(
          { namespace, name },
          { headers: iamHeaders }
        );

        expect(response.configuration).toBeDefined();
        expect(response.configuration?.namespace).toBe(namespace);
        expect(response.configuration?.name).toBe(name);
      });

      it("should update the existing configuration", async () => {
        const response = await adminClient.updateConfiguration(
          {
            namespace,
            name,
            configuration: {
              description: "Updated description",
              repositories: ["project-init/updated-repo"],
            },
          },
          { headers: iamHeaders }
        );

        expect(response.configuration).toBeDefined();
        expect(response.configuration?.description).toBe("Updated description");
        expect(response.configuration?.repositories).toEqual(["project-init/updated-repo"]);
      });

      it("should delete the existing configuration", async () => {
        await adminClient.deleteConfiguration(
          { namespace, name },
          { headers: iamHeaders }
        );

        // Verify deletion
        try {
          await adminClient.getConfiguration(
            { namespace, name },
            { headers: iamHeaders }
          );
          expect().fail("Expected getConfiguration to fail after deletion");
        } catch (e) {
          expect(e).toBeInstanceOf(ConnectError);
          expect((e as ConnectError).code).toBe(Code.NotFound);
        }
      });
    });
  });
});