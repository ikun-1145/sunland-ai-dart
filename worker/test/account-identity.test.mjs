import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { afterEach, test } from "node:test";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import worker from "../src/index.js";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

const rootDir = dirname(dirname(dirname(fileURLToPath(import.meta.url))));
const migrationSql = readFileSync(
  join(rootDir, "supabase/migrations/20260906110000_account_identity_state.sql"),
  "utf8",
);
const sanitizeSql = readFileSync(
  join(rootDir, "supabase/migrations/20260911130000_account_identity_sanitize.sql"),
  "utf8",
);

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

function memoryKv() {
  const values = new Map();
  return {
    values,
    async get(key) {
      return values.get(key) ?? null;
    },
    async put(key, value) {
      values.set(key, value);
    },
    async delete(key) {
      values.delete(key);
    },
  };
}

function env(overrides = {}) {
  return {
    APP_JWT_PRIMARY_SECRET: "application-secret",
    APP_JWT_LEGACY_SECRET: "application-secret",
    SUPABASE_LEGACY_JWT_SECRET: "database-secret",
    SUPABASE_URL: "https://database.example",
    SUPABASE_SERVICE_ROLE_KEY: "service-secret",
    SUNLAND_ACCOUNT_DELETE_INTERNAL_TOKEN: "internal-secret",
    ALLOWED_ORIGIN: "https://sunland.dev",
    CODE_STORE: memoryKv(),
    USAGE_KV: memoryKv(),
    ...overrides,
  };
}

function request(path, body = {}, payload = { id: "user-a", email: "a@example.com" }) {
  return new Request(`https://api.sunland.dev${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${sign(payload, "application-secret")}`,
      "content-type": "application/json",
      origin: "https://sunland.dev",
    },
    body: JSON.stringify(body),
  });
}

function internalRequest(path, body, token = "internal-secret") {
  return new Request(`https://api.sunland.dev${path}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-internal-token": token,
    },
    body: JSON.stringify(body),
  });
}

function activeStatusResponse(identityStatus = "active") {
  return Response.json([{
    is_banned: false,
    pro: false,
    identity_status: identityStatus,
  }]);
}

test("identity returns the JWT-derived user id and ignores a body user id", async () => {
  globalThis.fetch = async () => activeStatusResponse();
  const response = await worker.fetch(
    request("/v1/account/identity", { user_id: "attacker", email: "attacker@example.com" }),
    env(),
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    user_id: "user-a",
    email: "a@example.com",
    identity_status: "active",
  });
});

test("identity rejects a token with only an email and no stable user id", async () => {
  globalThis.fetch = async () => activeStatusResponse();
  const response = await worker.fetch(
    request("/v1/account/identity", {}, { email: "a@example.com" }),
    env(),
  );
  assert.equal(response.status, 401);
});

test("identity rejects deleting and retired identities", async () => {
  for (const identityStatus of ["deleting", "retired"]) {
    globalThis.fetch = async () => activeStatusResponse(identityStatus);
    const response = await worker.fetch(
      request("/v1/account/identity", {}, { id: "user-a", email: "a@example.com" }),
      env(),
    );
    assert.equal(response.status, 403);
    assert.deepEqual(await response.json(), { error: "ACCOUNT_NOT_ACTIVE" });
  }
});

test("account delete begin is internal-only and returns a verifiable revoked result", async () => {
  const calls = [];
  globalThis.fetch = async (url, init) => {
    calls.push({ url: String(url), body: JSON.parse(init.body) });
    return Response.json({
      code: "revoked",
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      user_id: "user-a",
      attempt_id: "attempt-abcdefghijklmnop",
      fencing_version: 1,
    });
  };

  const response = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );

  assert.equal(response.status, 200);
  assert.equal(calls[0].url.endsWith("/rest/v1/rpc/sunland_account_delete_begin"), true);
  assert.deepEqual(calls[0].body, {
    p_user_id: "user-a",
    p_deletion_job_id: "11111111-1111-4111-8111-111111111111",
    p_attempt_id: "attempt-abcdefghijklmnop",
    p_fencing_version: 1,
  });
  assert.deepEqual(await response.json(), {
    ok: true,
    code: "revoked",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });

  const unauthorized = await worker.fetch(
    internalRequest(
      "/v1/account-delete/begin",
      {
        deletion_job_id: "11111111-1111-4111-8111-111111111111",
        attempt_id: "attempt-abcdefghijklmnop",
        user_id: "user-a",
        fencing_version: 1,
      },
      "wrong-token",
    ),
    env(),
  );
  assert.equal(unauthorized.status, 401);
});

test("account delete begin maps already_revoked, conflict, and not-found safely", async () => {
  globalThis.fetch = async () => Response.json({
    code: "already_revoked",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const repeated = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(repeated.status, 200);
  assert.equal((await repeated.json()).code, "already_revoked");

  globalThis.fetch = async () => Response.json({
    code: "deletion_conflict",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const conflict = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(conflict.status, 409);

  globalThis.fetch = async () => Response.json({
    code: "user_not_found",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const missing = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(missing.status, 404);
});

test("account delete finalize is idempotent and maps invalid jobs to 409", async () => {
  globalThis.fetch = async () => Response.json({
    code: "retired",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const first = await worker.fetch(
    internalRequest("/v1/account-delete/finalize", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(first.status, 200);
  assert.equal((await first.json()).code, "retired");

  globalThis.fetch = async () => Response.json({
    code: "already_retired",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const second = await worker.fetch(
    internalRequest("/v1/account-delete/finalize", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(second.status, 200);
  assert.equal((await second.json()).code, "already_retired");

  globalThis.fetch = async () => Response.json({
    code: "not_deleting",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-abcdefghijklmnop",
    fencing_version: 1,
  });
  const conflict = await worker.fetch(
    internalRequest("/v1/account-delete/finalize", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
      fencing_version: 1,
    }),
    env(),
  );
  assert.equal(conflict.status, 409);
});

test("begin ownership_transferred returns the database-authoritative owner", async () => {
  globalThis.fetch = async () => Response.json({
    code: "ownership_transferred",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-BBBBBBBBBBBBBBBB",
    fencing_version: 2,
  });

  const response = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-BBBBBBBBBBBBBBBB",
      fencing_version: 2,
      user_id: "user-a",
    }),
    env(),
  );

  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    ok: true,
    code: "ownership_transferred",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-BBBBBBBBBBBBBBBB",
    fencing_version: 2,
  });
});

test("stale and fencing-conflicted begin/finalize are rejected", async () => {
  const body = {
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    attempt_id: "attempt-AAAAAAAAAAAAAAAA",
    fencing_version: 1,
    user_id: "user-a",
  };

  globalThis.fetch = async () => Response.json({
    code: "stale_attempt",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-BBBBBBBBBBBBBBBB",
    fencing_version: 2,
  });
  const staleBegin = await worker.fetch(
    internalRequest("/v1/account-delete/begin", body),
    env(),
  );
  assert.equal(staleBegin.status, 409);
  assert.equal((await staleBegin.json()).error, "DELETION_CONFLICT");

  globalThis.fetch = async () => Response.json({
    code: "fencing_conflict",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-BBBBBBBBBBBBBBBB",
    fencing_version: 2,
  });
  const fencingBegin = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      ...body,
      attempt_id: "attempt-AAAAAAAAAAAAAAAA",
      fencing_version: 2,
    }),
    env(),
  );
  assert.equal(fencingBegin.status, 409);

  globalThis.fetch = async () => Response.json({
    code: "stale_attempt",
    deletion_job_id: "11111111-1111-4111-8111-111111111111",
    user_id: "user-a",
    attempt_id: "attempt-BBBBBBBBBBBBBBBB",
    fencing_version: 2,
  });
  const staleFinalize = await worker.fetch(
    internalRequest("/v1/account-delete/finalize", body),
    env(),
  );
  assert.equal(staleFinalize.status, 409);
});

test("internal deletion mutations require a positive fencing_version", async () => {
  globalThis.fetch = async () => {
    throw new Error("should not call Supabase");
  };
  const response = await worker.fetch(
    internalRequest("/v1/account-delete/begin", {
      deletion_job_id: "11111111-1111-4111-8111-111111111111",
      attempt_id: "attempt-abcdefghijklmnop",
      user_id: "user-a",
    }),
    env(),
  );
  assert.equal(response.status, 400);
});

test("deleting and retired users cannot refresh, exchange database token, or call AI", async () => {
  for (const identityStatus of ["deleting", "retired"]) {
    globalThis.fetch = async () => activeStatusResponse(identityStatus);

    const refresh = await worker.fetch(
      request("/refresh", {}, { id: "user-a", email: "a@example.com" }),
      env(),
    );
    assert.equal(refresh.status, 403);
    assert.deepEqual(await refresh.json(), { error: "ACCOUNT_NOT_ACTIVE" });

    const databaseToken = await worker.fetch(
      request("/v1/database-token", {}, { id: "user-a", email: "a@example.com" }),
      env(),
    );
    assert.equal(databaseToken.status, 403);

    const ai = await worker.fetch(
      request("/", { messages: [{ role: "user", content: "hello" }] }, {
        id: "user-a",
        email: "a@example.com",
      }),
      env(),
    );
    assert.equal(ai.status, 403);
  }
});

test("same email re-registration creates a new user id instead of reusing retired identity", async () => {
  const environment = env();
  await environment.CODE_STORE.put("code:new%40example.com", "123456");
  const calls = [];
  globalThis.fetch = async (url, init = {}) => {
    calls.push({ url: String(url), init });
    if (String(url).includes("/rest/v1/user_profiles?email=")) {
      return Response.json([]);
    }
    if (String(url).endsWith("/rest/v1/user_profiles")) {
      return new Response(null, { status: 200 });
    }
    throw new Error(`unexpected fetch: ${url}`);
  };

  const response = await worker.fetch(
    new Request("https://api.sunland.dev/verify-code", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "new@example.com", code: "123456" }),
    }),
    environment,
  );

  assert.equal(response.status, 200);
  const result = await response.json();
  assert.notEqual(result.user.id, "retired-user-id");
  assert.match(result.user.id, /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
  assert.match(
    calls[0].url,
    /user_profiles\?email=eq\.new%40example\.com&identity_status=eq\.active&select=user_id/,
  );
});

test("migration stores deletion job/attempt and keeps retired emails re-registerable", () => {
  assert.match(migrationSql, /identity_status text not null default 'active'/);
  assert.match(migrationSql, /deletion_job_id uuid/);
  assert.match(migrationSql, /deletion_attempt_id text/);
  assert.match(migrationSql, /deletion_fencing_version bigint not null default 0/);
  assert.match(migrationSql, /retired_at timestamptz/);
  assert.match(migrationSql, /for update/);
  assert.match(migrationSql, /already_revoked/);
  assert.match(migrationSql, /deletion_conflict/);
  assert.match(migrationSql, /stale_attempt/);
  assert.match(migrationSql, /fencing_conflict/);
  assert.match(migrationSql, /ownership_transferred/);
  assert.match(migrationSql, /p_fencing_version < v_version/);
  assert.match(migrationSql, /p_fencing_version = v_version/);
  assert.match(migrationSql, /p_attempt_id is distinct from v_attempt/);
  assert.match(migrationSql, /identity_status is distinct from 'retired'/);
});

test("profile sanitize migration preserves retired tombstone and fencing", () => {
  assert.match(sanitizeSql, /profile_sanitized_at timestamptz/);
  assert.match(sanitizeSql, /sunland_account_delete_sanitize_profile/);
  assert.match(sanitizeSql, /email = null/);
  assert.match(sanitizeSql, /avatar_path = null/);
  assert.match(sanitizeSql, /pro = false/);
  assert.match(sanitizeSql, /user_id = p_user_id/);
  assert.match(sanitizeSql, /stale_attempt/);
  assert.match(sanitizeSql, /fencing_conflict/);
  assert.match(sanitizeSql, /already_sanitized/);
});
