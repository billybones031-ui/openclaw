import type { IncomingMessage, ServerResponse } from "node:http";
import { VERSION } from "../version.js";

export const AGENT_DISCOVERY_PATH = "/.well-known/openclaw-gateway";

/**
 * Handles GET /.well-known/openclaw-gateway — unauthenticated agent capabilities manifest.
 * Returns false if the request path doesn't match, allowing the caller to continue routing.
 */
export function handleAgentDiscoveryRequest(req: IncomingMessage, res: ServerResponse): boolean {
  const url = new URL(req.url ?? "/", "http://localhost");
  if (url.pathname !== AGENT_DISCOVERY_PATH) {
    return false;
  }

  const method = (req.method ?? "GET").toUpperCase();
  if (method !== "GET" && method !== "HEAD") {
    res.statusCode = 405;
    res.setHeader("Allow", "GET, HEAD");
    res.setHeader("Content-Type", "text/plain; charset=utf-8");
    res.end("Method Not Allowed");
    return true;
  }

  res.statusCode = 200;
  res.setHeader("Content-Type", "application/json; charset=utf-8");
  res.setHeader("Cache-Control", "no-store");
  const payload = JSON.stringify({
    name: "OpenClaw Gateway",
    type: "openclaw-gateway",
    version: VERSION,
    protocol: "openclaw-gateway/v1",
    capabilities: ["chat", "agents", "channels", "cron", "mcp", "skills"],
    healthUrl: "/health",
    wsPath: "/",
  });
  res.end(method === "HEAD" ? undefined : payload);
  return true;
}
