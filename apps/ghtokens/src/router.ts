import type { ConnectRouter } from "@connectrpc/connect";
import { registerTokenHandlers } from "./handlers/token.js";
import { registerAdminHandlers } from "./handlers/admin.js";

export default function (router: ConnectRouter) {
  registerTokenHandlers(router);
  registerAdminHandlers(router);
}
