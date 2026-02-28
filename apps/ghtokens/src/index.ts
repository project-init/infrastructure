import { connectNodeAdapter } from "@connectrpc/connect-node";
import * as http from "node:http";
import serverless from "serverless-http";
import routes from "./router.js";

const connectHandler = connectNodeAdapter({ routes });

const requestListener: http.RequestListener = (req, res) => {
  // Simple health check endpoint
  if (req.url === "/health" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  // Delegate all other requests to Connect RPC
  connectHandler(req, res);
};

// Export Lambda handler for Function URL
export const handler = serverless(requestListener);

// Start server locally if not running in AWS Lambda
if (process.env.NODE_ENV !== "production" && !process.env.LAMBDA_TASK_ROOT) {
  const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;
  const server = http.createServer(requestListener);
  server.listen(PORT, () => {
    console.log(`ghtokens service listening on port ${PORT}`);
  });
}
