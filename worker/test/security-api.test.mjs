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
  const operations = { get: 0, put: 0, delete: 0, list: 0 };
  return {
    values,
    operations,
    async get(key) {
      operations.get += 1;
      return values.get(key) ?? null;
    },
    async put(key, value) {
      operations.put += 1;
      values.set(key, value);
    },
    async delete(key) {
      operations.delete += 1;
      values.delete(key);
    },
    async list({ prefix = "" } = {}) {
      operations.list += 1;
      return {
        keys: [...values.keys()]
          .filter(name => name.startsWith(prefix))
          .map(name => ({ name })),
        list_complete: true,
      };
    },
  };
}

function resetKvOperations(...namespaces) {
  for (const namespace of namespaces) {
    for (const operation of Object.keys(namespace.operations)) {
      namespace.operations[operation] = 0;
    }
  }
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

function adminRequest(path, {
  method = "GET",
  body,
  token = "supabase-session",
} = {}) {
  const headers = {
    authorization: `Bearer ${token}`,
    origin: "https://sunland.dev",
  };
  if (body !== undefined) headers["content-type"] = "application/json";
  return new Request(`https://api.sunland.dev${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
}

function adminEnv(overrides = {}) {
  return env({
    ADMIN_AUTH_USER_ID: "11111111-1111-4111-8111-111111111111",
    ADMIN_EMAIL: "liuxizekali@outlook.com",
    ...overrides,
  });
}

function verifiedAdminUser(overrides = {}) {
  return {
    id: "11111111-1111-4111-8111-111111111111",
    email: "liuxizekali@outlook.com",
    email_confirmed_at: "2026-01-01T00:00:00.000Z",
    ...overrides,
  };
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

test("failed email delivery does not leave a cooldown or usable code", async () => {
  let mailAttempts = 0;
  globalThis.fetch = async (url) => {
    if (String(url).startsWith("https://gcaptcha4.geetest.com/validate")) {
      return Response.json({ result: "success" });
    }
    if (String(url) === "https://api.resend.com/emails") {
      mailAttempts += 1;
      return mailAttempts === 1
        ? new Response("upstream failure", { status: 503 })
        : Response.json({ id: "message-id" });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const environment = env({
    GEETEST_ID: "captcha-id",
    GEETEST_SERVER_KEY: "captcha-secret",
    RESEND_API_TOKEN: "resend-secret",
  });
  const email = "retry@example.com";
  const captcha = JSON.stringify({
    lot_number: "lot",
    captcha_output: "output",
    pass_token: "pass",
    gen_time: "now",
  });
  const sendRequest = () => new Request("https://api.sunland.dev/send-code", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ email, token: captcha }),
  });

  const firstResponse = await worker.fetch(sendRequest(), environment);
  assert.equal(firstResponse.status, 500);
  const key = encodeURIComponent(email);
  assert.equal(environment.CODE_STORE.values.has(`cooldown:${key}`), false);
  assert.equal(environment.CODE_STORE.values.has(`code:${key}`), false);

  const retryResponse = await worker.fetch(sendRequest(), environment);
  assert.equal(retryResponse.status, 200);
  assert.equal(environment.CODE_STORE.values.has(`cooldown:${key}`), true);
});

test("successful email delivery uses one read, two writes, and one delete", async () => {
  globalThis.fetch = async (url) => {
    if (String(url).startsWith("https://gcaptcha4.geetest.com/validate")) {
      return Response.json({ result: "success" });
    }
    if (String(url) === "https://api.resend.com/emails") {
      return Response.json({ id: "message-id" });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const environment = env({
    GEETEST_ID: "captcha-id",
    GEETEST_SERVER_KEY: "captcha-secret",
    RESEND_API_TOKEN: "resend-secret",
  });
  const response = await worker.fetch(
    new Request("https://api.sunland.dev/send-code", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: "audit@example.com",
        token: JSON.stringify({
          lot_number: "lot",
          captcha_output: "output",
          pass_token: "pass",
          gen_time: "now",
        }),
      }),
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(environment.CODE_STORE.operations, {
    get: 1,
    put: 2,
    delete: 1,
    list: 0,
  });
});

test("successful code verification uses three reads, one write, and two deletes", async () => {
  const environment = env();
  const email = "audit@example.com";
  const key = encodeURIComponent(email);
  await environment.CODE_STORE.put(`code:${key}`, "123456");
  resetKvOperations(environment.CODE_STORE);
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?email=")) {
      return Response.json([{ user_id: "user-a" }]);
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    new Request("https://api.sunland.dev/verify-code", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email, code: "123456" }),
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(environment.CODE_STORE.operations, {
    get: 3,
    put: 1,
    delete: 2,
    list: 0,
  });
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

test("retired activation claims return 410 before authentication or database access", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("unexpected upstream call");
  };
  const response = await worker.fetch(request("/v1/activation/claim", { code: "VALID_CODE" }), env());
  assert.equal(response.status, 410);
  assert.deepEqual(await response.json(), { error: "ACTIVATION_CODES_RETIRED" });
  assert.equal(called, false);
});

test("public announcement reads use the configured Supabase project and server-key aliases", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return new Response(JSON.stringify({ items: [], total: 0, page: 1, pageSize: 20 }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };
  const response = await worker.fetch(
    new Request("https://api.sunland.dev/v1/announcements"),
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
    "https://database-alias.example/rest/v1/rpc/sunland_public_announcements",
  );
  assert.equal(calls[0].init.headers.apikey, "sb_secret_server-alias");
  assert.equal(calls[0].init.headers.Authorization, undefined);
  assert.deepEqual(JSON.parse(calls[0].init.body), { p_page: 1, p_page_size: 20 });
});

test("Admin API rejects a second Auth identity even when the request body spoofs the fixed email and role", async () => {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    if (String(url).endsWith("/auth/v1/user")) {
      return Response.json(verifiedAdminUser({ id: "22222222-2222-4222-8222-222222222222" }));
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    adminRequest("/v1/admin/stats", {
      method: "POST",
      body: { email: "liuxizekali@outlook.com", userId: "business-admin", isAdmin: true, role: "admin" },
    }),
    adminEnv(),
  );

  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: "ADMIN_FORBIDDEN", message: "该账号没有管理权限" });
  assert.equal(calls.length, 1);
});

test("Admin API requires verified email, pinned Auth UUID, and exactly one business profile", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) {
      return Response.json([{ user_id: "business-profile-is-not-auth-uuid" }]);
    }
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_stats")) {
      return Response.json({ totalUsers: 12, currentProUsers: 2 });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(adminRequest("/v1/admin/stats"), adminEnv());

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { totalUsers: 12, currentProUsers: 2 });
  assert.equal(calls.length, 3);
  assert.equal(calls[0].init.headers.Authorization, "Bearer supabase-session");
  assert.match(calls[1].url, /user_profiles\?email=eq\.liuxizekali%40outlook\.com/);
  assert.equal(calls[2].url.endsWith("sunland_admin_stats"), true);
});

test("unverified email and duplicate business profiles cannot obtain Admin access", async () => {
  globalThis.fetch = async (url) => {
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser({ email_confirmed_at: null }));
    throw new Error(`unexpected fetch: ${url}`);
  };
  const unverified = await worker.fetch(adminRequest("/v1/admin/stats"), adminEnv());
  assert.equal(unverified.status, 403);

  globalThis.fetch = async (url) => {
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "one" }, { user_id: "two" }]);
    throw new Error(`unexpected fetch: ${url}`);
  };
  const duplicate = await worker.fetch(adminRequest("/v1/admin/stats"), adminEnv());
  assert.equal(duplicate.status, 403);
});

test("user list remains one current-page aggregation RPC at page sizes 20 and 100", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_list_users")) {
      return Response.json({ items: [], total: 0, page: 1, pageSize: JSON.parse(init.body).p_page_size });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const first = await worker.fetch(adminRequest("/v1/admin/users?pageSize=20"), adminEnv());
  const second = await worker.fetch(adminRequest("/v1/admin/users?pageSize=100"), adminEnv());
  assert.equal(first.status, 200);
  assert.equal(second.status, 200);
  const listCalls = calls.filter(call => call.url.endsWith("/rest/v1/rpc/sunland_admin_list_users"));
  assert.equal(listCalls.length, 2);
  assert.deepEqual(listCalls.map(call => JSON.parse(call.init.body).p_page_size), [20, 100]);
  assert.equal(calls.some(call => /conversations|history/.test(call.url)), false);
});

test("AI stats expose only aggregated current KV counters", async () => {
  const environment = adminEnv();
  const cst = new Date(Date.now() + 8 * 60 * 60 * 1000);
  const today = cst.toISOString().slice(0, 10);
  environment.USAGE_KV.values.set(`usage:user-a:${today}`, "2");
  environment.USAGE_KV.values.set(`usage:user-b:${today}`, "3");
  environment.USAGE_KV.values.set(`title_usage:user-a:${today}`, "1");
  environment.USAGE_KV.values.set("usage:old-user:2020-01-01", "99");
  globalThis.fetch = async url => {
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(adminRequest("/v1/admin/ai/stats"), environment);

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    date: today,
    freeChat: { successfulRequests: 5, trackedUsers: 2, complete: true },
    titleGeneration: { successfulRequests: 1, trackedUsers: 1, complete: true },
  });
  assert.equal(environment.USAGE_KV.operations.list, 2);
});

test("successful maintenance mutation relies on its single transactional RPC and does not create a separate success audit write", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_set_maintenance")) return Response.json({ enabled: true });
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(adminRequest("/v1/admin/system/maintenance", {
    method: "POST",
    body: { enabled: true, title: "维护中", message: "稍后恢复", estimatedEnd: "2026-09-05T00:00:00.000Z" },
  }), adminEnv());

  assert.equal(response.status, 200);
  assert.equal(calls.some(call => call.url.includes("sunland_admin_record_failed_action")), false);
  const mutation = calls.find(call => call.url.endsWith("sunland_admin_set_maintenance"));
  assert.equal(JSON.parse(mutation.init.body).p_admin_user_id, "11111111-1111-4111-8111-111111111111");
});

test("system status reads the real app_config primary key", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).includes("/rest/v1/app_config?config_key=eq.global")) {
      return Response.json([{ maintenance_enabled: false }]);
    }
    if (String(url) === "https://ai-core.sunland.dev/healthz") return Response.json({ status: "ok" });
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(adminRequest("/v1/admin/system/status"), adminEnv());

  assert.equal(response.status, 200);
  assert.equal(calls.some(call => call.url.includes("app_config?id=eq.global")), false);
});

test("announcement mutations keep one publish time and always clear the retired end time", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_create_announcement")) {
      return Response.json({ id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    adminRequest("/v1/admin/announcements", {
      method: "POST",
      body: {
        title: "维护通知",
        content: "服务即将维护。",
        startsAt: "2026-09-06T02:00:00.000Z",
        endsAt: "2026-09-07T02:00:00.000Z",
      },
    }),
    adminEnv(),
  );

  assert.equal(response.status, 200);
  const mutation = calls.find(call => call.url.endsWith("sunland_admin_create_announcement"));
  assert.deepEqual(JSON.parse(mutation.init.body), {
    p_admin_user_id: "11111111-1111-4111-8111-111111111111",
    p_title: "维护通知",
    p_content: "服务即将维护。",
    p_starts_at: "2026-09-06T02:00:00.000Z",
    p_ends_at: null,
  });
});

test("user ban is an authenticated, transactional Admin mutation", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_set_user_ban_with_reason")) {
      return Response.json({ userId: "target-user", isBanned: true, banReason: "滥用服务" });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    adminRequest("/v1/admin/users/target-user/ban", {
      method: "POST",
      body: { reason: "滥用服务" },
    }),
    adminEnv(),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    userId: "target-user",
    banned: true,
    banReason: "滥用服务",
  });
  assert.equal(calls.some(call => call.url.endsWith("sunland_admin_record_failed_action")), false);
  const mutation = calls.find(call => call.url.endsWith("sunland_admin_set_user_ban_with_reason"));
  assert.deepEqual(JSON.parse(mutation.init.body), {
    p_admin_user_id: "11111111-1111-4111-8111-111111111111",
    p_user_id: "target-user",
    p_is_banned: true,
    p_reason: "滥用服务",
  });
});

test("user ban rejects an empty reason before the business RPC", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_record_failed_action")) return Response.json(true);
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    adminRequest("/v1/admin/users/target-user/ban", {
      method: "POST",
      body: { reason: "   " },
    }),
    adminEnv(),
  );

  assert.equal(response.status, 400);
  assert.equal(calls.some(call => call.url.endsWith("sunland_admin_set_user_ban_with_reason")), false);
});

test("failed user ban writes a scrubbed failure audit after the business RPC", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_set_user_ban_with_reason")) {
      return Response.json({ message: "USER_NOT_FOUND" }, { status: 404 });
    }
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_record_failed_action")) return Response.json(true);
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    adminRequest("/v1/admin/users/missing-user/unban", { method: "POST" }),
    adminEnv(),
  );

  assert.equal(response.status, 404);
  assert.deepEqual(await response.json(), { error: "NOT_FOUND", message: "目标不存在" });
  const audit = calls.find(call => call.url.endsWith("sunland_admin_record_failed_action"));
  assert.deepEqual(JSON.parse(audit.init.body), {
    p_admin_user_id: "11111111-1111-4111-8111-111111111111",
    p_action: "user_unbanned",
    p_target_type: "user_profile",
    p_target_id: "missing-user",
    p_result: "NOT_FOUND",
    p_metadata: {},
  });
});

test("failed mutation rolls back through its RPC then records a scrubbed failure audit in a new request", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_set_maintenance")) {
      return Response.json({ message: "database unavailable" }, { status: 500 });
    }
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_record_failed_action")) return Response.json(true);
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(adminRequest("/v1/admin/system/maintenance", {
    method: "POST",
    body: { enabled: false, title: "维护结束", message: "服务已恢复" },
  }), adminEnv());

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "DATABASE_ERROR", message: "操作暂时不可用" });
  const failure = calls.find(call => call.url.endsWith("/rest/v1/rpc/sunland_admin_record_failed_action"));
  const audit = JSON.parse(failure.init.body);
  assert.deepEqual(audit, {
    p_admin_user_id: "11111111-1111-4111-8111-111111111111",
    p_action: "maintenance_disabled",
    p_target_type: "app_config",
    p_target_id: "global",
    p_result: "DATABASE_ERROR",
    p_metadata: {},
  });
  assert.doesNotMatch(JSON.stringify(audit), /supabase-session|service-secret|Authorization|JWT/i);
});

test("published announcements cannot be physically deleted and the conflict is failure-audited", async () => {
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).endsWith("/auth/v1/user")) return Response.json(verifiedAdminUser());
    if (String(url).includes("/rest/v1/user_profiles?email=")) return Response.json([{ user_id: "business-admin" }]);
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_delete_draft_announcement")) {
      return Response.json({ message: "ANNOUNCEMENT_WAS_PUBLISHED" }, { status: 409 });
    }
    if (String(url).endsWith("/rest/v1/rpc/sunland_admin_record_failed_action")) return Response.json(true);
    throw new Error(`unexpected fetch: ${url}`);
  };
  const id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
  const response = await worker.fetch(adminRequest(`/v1/admin/announcements/${id}`, { method: "DELETE" }), adminEnv());
  assert.equal(response.status, 409);
  assert.deepEqual(await response.json(), { error: "CONFLICT", message: "当前状态不允许此操作" });
  assert.equal(calls.some(call => call.url.endsWith("sunland_admin_record_failed_action")), true);
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

test("conversation title summarizes only the supplied first exchange without consuming chat quota", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  const cst = new Date(Date.now() + 8 * 60 * 60 * 1000);
  const today = cst.toISOString().slice(0, 10);
  const chatUsageKey = `usage:user-a:${today}`;
  await environment.USAGE_KV.put(chatUsageKey, "20");
  resetKvOperations(environment.USAGE_KV);
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: false }]);
    }
    return Response.json({
      choices: [{ message: { content: "「缓存一致性修复。」" } }],
    });
  };

  const response = await worker.fetch(
    request("/v1/conversation-title", {
      conversationId: "conversation-1",
      userMessage: "用户第一次提问",
      aiMessage: "AI 第一次回复",
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { title: "缓存一致性修复" });
  assert.equal(calls.length, 2);
  const upstreamBody = JSON.parse(calls[1].init.body);
  assert.equal(upstreamBody.model, "deepseek-v4-flash");
  assert.equal(upstreamBody.stream, false);
  assert.deepEqual(upstreamBody.thinking, { type: "disabled" });
  assert.match(upstreamBody.messages[1].content, /用户第一次提问/u);
  assert.match(upstreamBody.messages[1].content, /AI 第一次回复/u);
  const usageKeys = [...environment.USAGE_KV.values.keys()];
  assert.equal(environment.USAGE_KV.values.get(chatUsageKey), "20");
  const titleUsageKey = usageKeys.find(key => key.startsWith("title_usage:user-a:"));
  assert.equal(environment.USAGE_KV.values.get(titleUsageKey), "1");
  assert.deepEqual(environment.USAGE_KV.operations, {
    get: 2,
    put: 2,
    delete: 0,
    list: 0,
  });
});

test("free AI requests count quota, keyword, and rate-limit KV operations", async () => {
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: false }]);
    }
    return new Response("data: [DONE]\n\n", {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
      model: "deepseek-v4-flash",
    }),
    environment,
  );
  assert.equal(response.status, 200);
  await response.arrayBuffer();
  assert.deepEqual(environment.USAGE_KV.operations, {
    get: 3,
    put: 2,
    delete: 0,
    list: 0,
  });
});

test("quota exhaustion stops before keyword and rate-limit KV operations", async () => {
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  const cst = new Date(Date.now() + 8 * 60 * 60 * 1000);
  const today = cst.toISOString().slice(0, 10);
  await environment.USAGE_KV.put(`usage:user-a:${today}`, "20");
  resetKvOperations(environment.USAGE_KV);
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: false }]);
    }
    throw new Error("DeepSeek must not be called after quota exhaustion");
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
    }),
    environment,
  );
  assert.equal(response.status, 429);
  assert.deepEqual(environment.USAGE_KV.operations, {
    get: 1,
    put: 0,
    delete: 0,
    list: 0,
  });
});

test("upstream AI failure does not write the daily quota", async () => {
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: false }]);
    }
    return new Response("upstream failure", { status: 503 });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
    }),
    environment,
  );
  assert.equal(response.status, 502);
  assert.deepEqual(environment.USAGE_KV.operations, {
    get: 3,
    put: 1,
    delete: 0,
    list: 0,
  });
});

test("KV diagnostics expose logical operations without raw keys", async () => {
  const logs = [];
  const originalLog = console.log;
  console.log = (...args) => logs.push(args.join(" "));
  try {
    const environment = env({
      DEEPSEEK_API_KEY: "test-deepseek-key",
      KV_DIAGNOSTICS: "1",
    });
    globalThis.fetch = async (url) => {
      if (String(url).includes("/rest/v1/user_profiles?")) {
        return Response.json([{ is_banned: false, pro: false }]);
      }
      return new Response("data: [DONE]\n\n", {
        status: 200,
        headers: { "content-type": "text/event-stream" },
      });
    };

    const response = await worker.fetch(
      request("/", {
        messages: [{ role: "user", content: "hello" }],
      }),
      environment,
    );
    assert.equal(response.status, 200);
    assert.match(logs.join("\n"), /namespace=USAGE_KV operation=ai-usage-check/u);
    assert.match(logs.join("\n"), /namespace=USAGE_KV operation=ai-blocked-keywords-read/u);
    assert.match(logs.join("\n"), /namespace=USAGE_KV operation=ai-rate-limit-write/u);
    assert.match(logs.join("\n"), /namespace=USAGE_KV operation=ai-usage-update/u);
    assert.doesNotMatch(logs.join("\n"), /usage:user-a|Authorization|hello/u);
  } finally {
    console.log = originalLog;
  }
});

test("conversation title rejects incomplete exchanges before the AI request", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    return Response.json([{ is_banned: false, pro: false }]);
  };

  const response = await worker.fetch(
    request("/v1/conversation-title", {
      conversationId: "conversation-1",
      userMessage: "只有用户消息",
      aiMessage: "   ",
    }),
    env({ DEEPSEEK_API_KEY: "test-deepseek-key" }),
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), { error: "invalid conversation exchange" });
  assert.equal(calls.length, 1);
});

test("Pro model uses user_profiles.pro despite a stale negative KV entry", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  await environment.USAGE_KV.put("pro:user-a", "0");
  resetKvOperations(environment.USAGE_KV);
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: true }]);
    }
    return new Response('data: [DONE]\n\n', {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello from Pro" }],
      model: "deepseek-v4-pro",
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-model"), "deepseek-v4-pro");
  assert.equal(response.headers.get("x-remain"), "-1");
  assert.equal(calls.length, 2);
  assert.equal(
    calls[0].url,
    "https://database.example/rest/v1/user_profiles?user_id=eq.user-a&select=is_banned,pro&limit=1",
  );
  assert.equal(calls.some(call => call.url.includes("/activation_codes?")), false);
  assert.equal(JSON.parse(calls[1].init.body).model, "deepseek-v4-pro");
  assert.deepEqual(environment.USAGE_KV.operations, {
    get: 2,
    put: 1,
    delete: 0,
    list: 0,
  });
});

test("legacy positive KV cannot grant Pro when user_profiles.pro is false", async () => {
  let deepseekCalled = false;
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  await environment.USAGE_KV.put("pro:user-a", "1");
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: false }]);
    }
    deepseekCalled = true;
    throw new Error("unexpected DeepSeek request");
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
      model: "deepseek-v4-pro",
    }),
    environment,
  );

  assert.equal(response.status, 403);
  assert.deepEqual(await response.json(), { error: "PRO_REQUIRED" });
  assert.equal(deepseekCalled, false);
});

test("image content is preserved and routed to the DeepSeek vision model", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    return new Response(
      'data: {"choices":[{"delta":{"content":"看到了"}}]}\n\ndata: [DONE]\n\n',
      { status: 200, headers: { "content-type": "text/event-stream" } },
    );
  };

  const imageDataUrl = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=";
  const response = await worker.fetch(
    request("/", {
      messages: [
        { role: "system", content: "Be helpful" },
        {
          role: "user",
          content: [
            { type: "text", text: "这张图片里有什么？" },
            {
              type: "image_url",
              image_url: { url: imageDataUrl, detail: "auto" },
            },
            {
              type: "image_url",
              image_url: { url: imageDataUrl, detail: "low" },
            },
          ],
        },
      ],
      model: "deepseek-v4-pro",
      deep: true,
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-model"), "deepseek-v4-flash-vision-exp");
  assert.equal(response.headers.get("x-deep"), "1");
  assert.match(await response.text(), /看到了/);
  const upstreamBody = JSON.parse(calls[1].init.body);
  assert.equal(upstreamBody.model, "deepseek-v4-flash-vision-exp");
  assert.deepEqual(upstreamBody.thinking, { type: "enabled" });
  assert.deepEqual(upstreamBody.messages[1].content[1], {
    type: "image_url",
    image_url: { url: imageDataUrl, detail: "auto" },
  });
  assert.deepEqual(upstreamBody.messages[1].content[2], {
    type: "image_url",
    image_url: { url: imageDataUrl, detail: "low" },
  });
});

test("vision requests never fall back to a text-only model", async () => {
  const tinyPng = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Y9ZQmcAAAAASUVORK5CYII=";
  const upstreamRequests = [];
  globalThis.fetch = async (url, init = {}) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    const upstreamBody = JSON.parse(init.body);
    upstreamRequests.push({
      model: upstreamBody.model,
      thinking: upstreamBody.thinking,
    });
    return Response.json({ error: "vision unavailable" }, { status: 503 });
  };

  const environment = env({ DEEPSEEK_API_KEY: "deepseek-secret" });
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
  assert.deepEqual(upstreamRequests, [{
    model: "deepseek-v4-flash-vision-exp",
    thinking: { type: "disabled" },
  }]);
});

test("inline image MIME must match the decoded file signature", async () => {
  let deepseekCalled = false;
  globalThis.fetch = async (url) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    deepseekCalled = true;
    throw new Error("unexpected DeepSeek request");
  };

  const environment = env({ DEEPSEEK_API_KEY: "deepseek-secret" });
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
  assert.deepEqual(await response.json(), { error: "image signature mismatch" });
  assert.equal(deepseekCalled, false);
});

test("text-only chat explicitly disables DeepSeek thinking by default", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    return new Response('data: [DONE]\n\n', {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "hello" }],
      model: "deepseek-v4-flash",
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-model"), "deepseek-v4-flash");
  const upstreamBody = JSON.parse(calls[1].init.body);
  assert.equal(upstreamBody.model, "deepseek-v4-flash");
  assert.deepEqual(upstreamBody.thinking, { type: "disabled" });
  assert.deepEqual(upstreamBody.messages, [
    { role: "user", content: "hello" },
  ]);
});

test("deep thinking stays enabled when the Pro model falls back to flash", async () => {
  const upstreamBodies = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false, pro: true }]);
    }
    const upstreamBody = JSON.parse(init.body);
    upstreamBodies.push(upstreamBody);
    if (upstreamBody.model === "deepseek-v4-pro") {
      return Response.json({ error: "temporary" }, { status: 503 });
    }
    return new Response('data: [DONE]\n\n', {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "think carefully" }],
      model: "deepseek-v4-pro",
      deep: true,
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.equal(response.headers.get("x-deep"), "1");
  assert.deepEqual(
    upstreamBodies.map(body => ({ model: body.model, thinking: body.thinking })),
    [
      { model: "deepseek-v4-pro", thinking: { type: "enabled" } },
      { model: "deepseek-v4-flash", thinking: { type: "enabled" } },
    ],
  );
});

test("content moderation and ordinary replies both disable thinking", async () => {
  const upstreamBodies = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url, init) => {
    if (String(url).includes("/rest/v1/user_profiles?")) {
      return Response.json([{ is_banned: false }]);
    }
    const upstreamBody = JSON.parse(init.body);
    upstreamBodies.push(upstreamBody);
    if (upstreamBody.stream === false) {
      return Response.json({
        choices: [{ message: { content: "ok" } }],
      });
    }
    return new Response('data: [DONE]\n\n', {
      status: 200,
      headers: { "content-type": "text/event-stream" },
    });
  };

  const response = await worker.fetch(
    request("/", {
      messages: [{ role: "user", content: "vpn" }],
      model: "deepseek-v4-flash",
      deep: false,
    }),
    environment,
  );

  assert.equal(response.status, 200);
  assert.deepEqual(
    upstreamBodies.map(body => body.thinking),
    [{ type: "disabled" }, { type: "disabled" }],
  );
});

test("image blocks are rejected outside user messages", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return Response.json([{ is_banned: false }]);
  };

  const response = await worker.fetch(
    request("/", {
      messages: [
        {
          role: "assistant",
          content: [
            {
              type: "image_url",
              image_url: { url: "data:image/jpeg;base64,/9j/2Q==" },
            },
          ],
        },
      ],
    }),
    environment,
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: "images are only allowed in user messages",
  });
  assert.equal(calls.length, 1);
});

test("external image URLs are rejected by the app gateway", async () => {
  const calls = [];
  const environment = env({ DEEPSEEK_API_KEY: "test-deepseek-key" });
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return Response.json([{ is_banned: false }]);
  };

  const response = await worker.fetch(
    request("/", {
      messages: [
        {
          role: "user",
          content: [
            { type: "text", text: "看看这张图" },
            {
              type: "image_url",
              image_url: { url: "https://example.com/image.jpg" },
            },
          ],
        },
      ],
    }),
    environment,
  );

  assert.equal(response.status, 400);
  assert.deepEqual(await response.json(), {
    error: "only inline JPEG, PNG, GIF, or WebP images are allowed",
  });
  assert.equal(calls.length, 1);
});

test("user status failures fail closed on protected AI routes", async () => {
  globalThis.fetch = async () => Response.json(
    { error: "database unavailable" },
    { status: 503 },
  );

  const response = await worker.fetch(
    request("/", { messages: [{ role: "user", content: "hello" }] }),
    env(),
  );

  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "User status unavailable" });
});

test("retired activation route never parses or validates legacy codes", async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error("unexpected upstream call");
  };
  const response = await worker.fetch(
    request("/v1/activation/claim", { code: "!" }),
    env(),
  );
  assert.equal(response.status, 410);
  assert.equal(called, false);
});
