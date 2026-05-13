import { describe, expect, it } from "vitest";
import {
  AUTH_NONE,
  createRequest,
  createResponse,
  dispatchRequest,
  withGatewayServer,
} from "./server-http.test-harness.js";

describe("gateway agent discovery endpoint", () => {
  it("returns agent manifest JSON for GET /.well-known/openclaw-gateway", async () => {
    await withGatewayServer({
      prefix: "discovery-get",
      resolvedAuth: AUTH_NONE,
      run: async (server) => {
        const req = createRequest({ path: "/.well-known/openclaw-gateway" });
        const { res, getBody } = createResponse();
        await dispatchRequest(server, req, res);

        expect(res.statusCode).toBe(200);
        const body = JSON.parse(getBody());
        expect(body.type).toBe("openclaw-gateway");
        expect(body.protocol).toBe("openclaw-gateway/v1");
        expect(Array.isArray(body.capabilities)).toBe(true);
        expect(body.healthUrl).toBe("/health");
        expect(body.wsPath).toBe("/");
      },
    });
  });

  it("returns 200 with no body for HEAD /.well-known/openclaw-gateway", async () => {
    await withGatewayServer({
      prefix: "discovery-head",
      resolvedAuth: AUTH_NONE,
      run: async (server) => {
        const req = createRequest({ path: "/.well-known/openclaw-gateway", method: "HEAD" });
        const { res, getBody } = createResponse();
        await dispatchRequest(server, req, res);

        expect(res.statusCode).toBe(200);
        expect(getBody()).toBe("");
      },
    });
  });

  it("returns 405 with Allow header for non-GET/HEAD methods", async () => {
    await withGatewayServer({
      prefix: "discovery-post",
      resolvedAuth: AUTH_NONE,
      run: async (server) => {
        const req = createRequest({ path: "/.well-known/openclaw-gateway", method: "POST" });
        const { res } = createResponse();
        await dispatchRequest(server, req, res);

        expect(res.statusCode).toBe(405);
        expect(res.setHeader).toHaveBeenCalledWith("Allow", "GET, HEAD");
      },
    });
  });

  it("does not intercept unrelated paths", async () => {
    await withGatewayServer({
      prefix: "discovery-passthrough",
      resolvedAuth: AUTH_NONE,
      run: async (server) => {
        const req = createRequest({ path: "/some-other-path" });
        const { res, getBody } = createResponse();
        await dispatchRequest(server, req, res);

        const body = getBody();
        expect(body).not.toContain("openclaw-gateway");
      },
    });
  });
});
