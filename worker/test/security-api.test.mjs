import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { afterEach, test } from "node:test";

import worker from "../src/index.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

function encode(value) {
  return Buffer.from(JSON.stringify(value)).toString("base64url");
}

function sign(payload, secret, expiresIn = 3600) {
  const now = Math.floor(Date.now() / 1000);
  const data = `${encode({ alg: "HS256", typ: "JWT" })}.${encode({
    ...payload,
    iat: now,
    exp: now + expiresIn,
  })}`;
  return `${data}.${createHmac("sha256", secret).update(data).digest("base64url")}`;
}

function decode(token) {
  return JSON.parse(Buffer.from(token.split(".")[1], "base64url").toString("utf8"));
}

function isSignedBy(token, secret) {
  const [header, payload, signature] = token.split(".");
  const expected = createHmac("sha256", secret)
    .update(`${header}.${payload}`)
    .digest("base64url");
  return signature === expected;
}

function memoryKv() {
  const values = new Map();
  return {
    values,
    async get(key) { return values.get(key) ?? null; },
    async put(key, value) { values.set(key, value); },
    async delete(key) { values.delete(key); },
  };
}

function env(overrides = {}) {
  return {
    JWT_SECRET: "application-secret",
    SUPABASE_JWT_SECRET: "database-secret",
    SUPABASE_URL: "https://database.example",
    SUPABASE_SERVICE_ROLE_KEY: "service-secret",
    ALLOWED_ORIGIN: "https://sunland.dev",
    CODE_STORE: memoryKv(),
    USAGE_KV: memoryKv(),
    ...overrides,
  };
}

function request(
  path,
  body = {},
  payload = { id: "user-a", email: "a@example.com" },
  secret = "application-secret",
) {
  return new Request(`https://api.sunland.dev${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${sign(payload, secret)}`,
      "content-type": "application/json",
      origin: "https://sunland.dev",
    },
    body: JSON.stringify(body),
  });
}

test("rotation bridge verifies primary and legacy tokens but still signs with legacy", async () => {
  const environment = env({
    JWT_SECRET: "",
    APP_JWT_PRIMARY_SECRET: "primary-secret",
    APP_JWT_LEGACY_SECRET: "legacy-secret",
  });
  const primaryResponse = await worker.fetch(
    request("/refresh", {}, undefined, "primary-secret"),
    environment,
  );
  assert.equal(primaryResponse.status, 200);
  const primaryResult = await primaryResponse.json();
  assert.equal(isSignedBy(primaryResult.token, "legacy-secret"), true);
  assert.equal(isSignedBy(primaryResult.token, "primary-secret"), false);

  const legacyResponse = await worker.fetch(
    request("/v1/database-token", {}, undefined, "legacy-secret"),
    environment,
  );
  assert.equal(legacyResponse.status, 200);
});

test("database token is short-lived, authenticated, and ignores a body user id", async () => {
  const response = await worker.fetch(
    request("/v1/database-token", { userId: "attacker" }),
    env(),
  );
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  const result = await response.json();
  assert.equal(result.expiresIn, 900);
  const claims = decode(result.token);
  assert.equal(claims.sub, "user-a");
  assert.equal(claims.id, "user-a");
  assert.equal(claims.role, "authenticated");
  assert.equal(claims.aud, "authenticated");
  assert.equal(claims.exp - claims.iat, 900);
});

test("database token fails closed when its signing secret is unavailable", async () => {
  const response = await worker.fetch(
    request("/v1/database-token"),
    env({ SUPABASE_JWT_SECRET: "" }),
  );
  assert.equal(response.status, 503);
});

test("database token supports the explicit legacy Supabase JWT alias", async () => {
  const response = await worker.fetch(
    request("/v1/database-token"),
    env({
      SUPABASE_JWT_SECRET: "",
      SUPABASE_LEGACY_JWT_SECRET: "database-alias-secret",
    }),
  );
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(isSignedBy(result.token, "database-alias-secret"), true);
});

test("expired application JWT is rejected before protected routes", async () => {
  const expired = sign(
    { id: "user-a", email: "a@example.com" },
    "application-secret",
    -1,
  );
  const response = await worker.fetch(
    new Request("https://api.sunland.dev/v1/database-token", {
      method: "POST",
      headers: {
        authorization: `Bearer ${expired}`,
        "content-type": "application/json",
      },
      body: "{}",
    }),
    env(),
  );
  assert.equal(response.status, 401);
});

test("activation claim uses the verified user and service-role RPC", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    return new Response(JSON.stringify("success"), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  const environment = env();
  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "VALID_CODE", userId: "attacker" }),
    environment,
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { result: "success" });
  assert.equal(calls.length, 2);
  assert.equal(
    calls[0].url,
    "https://database.example/rest/v1/user_profiles?user_id=eq.user-a&select=is_banned&limit=1",
  );
  assert.equal(calls[0].init.headers.Authorization, "Bearer service-secret");
  assert.equal(calls[1].url, "https://database.example/rest/v1/rpc/sunland_claim_activation_code");
  assert.equal(calls[1].init.headers.Authorization, "Bearer service-secret");
  assert.deepEqual(JSON.parse(calls[1].init.body), {
    p_user_id: "user-a",
    p_code: "VALID_CODE",
  });
  assert.equal(environment.USAGE_KV.values.get("pro:user-a"), "1");
});

test("staging safety switch blocks activation writes", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("unexpected upstream call");
  };
  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "VALID_CODE" }),
    env({ ACTIVATION_CLAIM_ENABLED: "false" }),
  );
  assert.equal(response.status, 503);
  assert.equal(called, false);
});

test("Supabase project and server-key aliases replace legacy names", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    return new Response(JSON.stringify("success"), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "VALID_CODE" }),
    env({
      SUPABASE_URL: "",
      SUPABASE_SERVICE_ROLE_KEY: "",
      SUPABASE_PROJECT_URL: "https://database-alias.example",
      SUPABASE_SECRET_KEY: "sb_secret_server-alias",
    }),
  );
  assert.equal(response.status, 200);
  assert.equal(
    calls[0].url,
    "https://database-alias.example/rest/v1/user_profiles?user_id=eq.user-a&select=is_banned&limit=1",
  );
  assert.equal(calls[0].init.headers.apikey, "sb_secret_server-alias");
  assert.equal(calls[0].init.headers.Authorization, undefined);
  assert.equal(calls[1].url, "https://database-alias.example/rest/v1/rpc/sunland_claim_activation_code");
  assert.equal(calls[1].init.headers.apikey, "sb_secret_server-alias");
  assert.equal(calls[1].init.headers.Authorization, undefined);
});

test("banned users are rejected before the AI upstream request", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return Response.json([{ is_banned: true }]);
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
      model: "deepseek-v4-flash",
    }),
    env(),
  );

  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: "ACCOUNT_BANNED" });
  assert.equal(calls.length, 1);
  assert.match(calls[0].url, /\/rest\/v1\/user_profiles\?/);
});

test("AI route preserves a valid inline image and selects the DeepSeek vision model", async () => {
  const tinyPng = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=";
  let upstreamBody = null;
  globalThis.fetch = async (url, init = {}) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    assert.equal(String(url), "https://api.deepseek.com/v1/chat/completions");
    upstreamBody = JSON.parse(init.body);
    return new Response("data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n", {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const environment = env({ DEEPSEEK_API_KEY: "deepseek-secret" });
  environment.USAGE_KV.values.set("pro:user-a", "0");
  const response = await worker.fetch(
    request("/", {
      model: "deepseek-v4-flash",
      messages: [{
        role: "user",
        content: [
          { type: "text", text: "Describe this image" },
          {
            type: "image_url",
            image_url: {
              url: `data:image/png;base64,${tinyPng}`,
              detail: "original",
            },
          },
        ],
      }],
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-model"), "deepseek-v4-flash-vision-exp");
  assert.equal(upstreamBody.model, "deepseek-v4-flash-vision-exp");
  assert.equal(upstreamBody.messages[0].content[0].text, "Describe this image");
  assert.equal(upstreamBody.messages[0].content[1].image_url.url, `data:image/png;base64,${tinyPng}`);
});

test("AI route never falls back to a text-only model when the vision request fails", async () => {
  const tinyPng = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=";
  const upstreamModels = [];
  globalThis.fetch = async (url, init = {}) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    assert.equal(String(url), "https://api.deepseek.com/v1/chat/completions");
    upstreamModels.push(JSON.parse(init.body).model);
    return Response.json({ error: "vision unavailable" }, { status: 503 });
  };

  const environment = env({ DEEPSEEK_API_KEY: "deepseek-secret" });
  environment.USAGE_KV.values.set("pro:user-a", "0");
  const response = await worker.fetch(
    request("/", {
      model: "deepseek-v4-pro",
      messages: [{
        role: "user",
        content: [
          { type: "text", text: "Describe this image without OCR" },
          {
            type: "image_url",
            image_url: { url: `data:image/png;base64,${tinyPng}`, detail: "original" },
          },
        ],
      }],
    }),
    environment,
  );

  assert.equal(response.status, 502);
  assert.deepEqual(upstreamModels, ["deepseek-v4-flash-vision-exp"]);
});

test("AI route rejects an inline image whose declared MIME does not match its signature", async () => {
  let deepseekCalled = false;
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    deepseekCalled = true;
    throw new Error("unexpected DeepSeek request");
  };

  const environment = env({ DEEPSEEK_API_KEY: "deepseek-secret" });
  environment.USAGE_KV.values.set("pro:user-a", "0");
  const response = await worker.fetch(
    request("/", {
      messages: [{
        role: "user",
        content: [{
          type: "image_url",
          image_url: { url: "data:image/jpeg;base64,iVBORw0KGgoAAAANSUhEUg==" },
        }],
      }],
    }),
    environment,
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid image input" });
  assert.equal(deepseekCalled, false);
});

test("user status failures fail closed on protected business routes", async () => {
  globalThis.fetch = async () => Response.json(
    { error: "database unavailable" },
    { status: 503 },
  );

  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "VALID_CODE" }),
    env(),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "User status unavailable" });
});

test("invalid activation code is rejected without reaching Supabase", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("unexpected upstream call");
  };
  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "!" }),
    env(),
  );
  assert.equal(response.status, 400);
  assert.equal(called, false);
});
