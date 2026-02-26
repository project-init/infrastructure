import { Layer, ManagedRuntime } from "effect";
import { OIDCValidatorLayer } from "./services/oidc.js";
import { AuthRulesEngineLayer } from "./services/auth-rules.js";
import { RepositoryLayer } from "./services/repository.js";
import { SecretsManagerLayer, GitHubAppLayer } from "./services/github.js";

const AppLayer = Layer.mergeAll(
  OIDCValidatorLayer,
  AuthRulesEngineLayer,
  RepositoryLayer(process.env.TABLE_NAME || "ghtokens-table"),
  SecretsManagerLayer,
).pipe(
  Layer.provideMerge(GitHubAppLayer)
);

export const appRuntime = ManagedRuntime.make(AppLayer);
