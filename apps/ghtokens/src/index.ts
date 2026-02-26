import { connectNodeAdapter } from "@connectrpc/connect-node";
import * as http from "node:http";
import routes from "./router.js";

const PORT = process.env.PORT ? parseInt(process.env.PORT, 10) : 8080;

const connectHandler = connectNodeAdapter({ routes });

const server = http.createServer((req, res) => {
  // Simple health check endpoint
  if (req.url === "/health" && req.method === "GET") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok" }));
    return;
  }

  // Delegate all other requests to Connect RPC
  connectHandler(req, res);
});

server.listen(PORT, () => {
  console.log(`ghtokens service listening on port ${PORT}`);
});
