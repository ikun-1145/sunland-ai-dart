import assert from "node:assert/strict";
import test from "node:test";

import worker from "../src/index.js";

const env = { ALLOWED_ORIGIN: "https://sunland.dev" };
const version = "1.4.2+31";
const ipaUrl = `https://api.sunland.dev/v1/download/ipa?v=${encodeURIComponent(version)}`;

function installRuntime({ cachedResponse, upstreamResponse } = {}) {
  const originalFetch = globalThis.fetch;
  const originalCaches = globalThis.caches;
  const cacheMatches = [];
  const cachePuts = [];
  const upstreamRequests = [];
  const backgroundTasks = [];
  let finished = false;

  Object.defineProperty(globalThis, "caches", {
    configurable: true,
    value: {
      default: {
        async match(request) {
          cacheMatches.push(request);
          return typeof cachedResponse === "function"
            ? cachedResponse(request)
            : cachedResponse;
        },
        async put(request, response) {
          cachePuts.push({
            request,
            response,
            body: new Uint8Array(await response.arrayBuffer()),
          });
        },
      },
    },
  });

  globalThis.fetch = async (input, init = {}) => {
    upstreamRequests.push({ input: String(input), init });
    if (typeof upstreamResponse === "function") {
      return upstreamResponse(input, init);
    }
    if (upstreamResponse) return upstreamResponse;
    throw new Error("unexpected upstream fetch");
  };

  return {
    cacheMatches,
    cachePuts,
    upstreamRequests,
    ctx: {
      waitUntil(promise) {
        backgroundTasks.push(promise);
      },
    },
    async finish() {
      if (finished) return;
      finished = true;
      await Promise.all(backgroundTasks);
      globalThis.fetch = originalFetch;
      if (originalCaches === undefined) {
        delete globalThis.caches;
      } else {
        Object.defineProperty(globalThis, "caches", {
          configurable: true,
          value: originalCaches,
        });
      }
    },
  };
}

test("download proxy validates platform, version, and method before fetching", async () => {
  const runtime = installRuntime();
  try {
    const missingVersion = await worker.fetch(
      new Request("https://api.sunland.dev/v1/download/ipa"),
      env,
      runtime.ctx,
    );
    assert.equal(missingVersion.status, 400);

    const invalidPlatform = await worker.fetch(
      new Request(`https://api.sunland.dev/v1/download/exe?v=${encodeURIComponent(version)}`),
      env,
      runtime.ctx,
    );
    assert.equal(invalidPlatform.status, 404);

    const invalidMethod = await worker.fetch(
      new Request(ipaUrl, { method: "POST", body: "{}" }),
      env,
      runtime.ctx,
    );
    assert.equal(invalidMethod.status, 405);
    assert.equal(invalidMethod.headers.get("allow"), "GET, HEAD");
    assert.equal(runtime.upstreamRequests.length, 0);
  } finally {
    await runtime.finish();
  }
});

test("download proxy serves a cached full asset without contacting GitHub", async () => {
  const runtime = installRuntime({
    cachedResponse: new Response("cached-ipa", {
      status: 200,
      headers: {
        "content-length": "10",
        etag: '"cached"',
      },
    }),
  });
  try {
    const response = await worker.fetch(new Request(ipaUrl), env, runtime.ctx);

    assert.equal(response.status, 200);
    assert.equal(await response.text(), "cached-ipa");
    assert.equal(response.headers.get("x-sunland-cache"), "HIT");
    assert.equal(response.headers.get("content-disposition"), `attachment; filename="sunland-ai-${version}.ipa"`);
    assert.equal(runtime.upstreamRequests.length, 0);
  } finally {
    await runtime.finish();
  }
});

test("download proxy streams a full asset and schedules a cache write", async () => {
  const payload = new TextEncoder().encode("fresh-ipa");
  const runtime = installRuntime({
    upstreamResponse: new Response(payload, {
      status: 200,
      headers: {
        "content-length": String(payload.byteLength),
        etag: '"fresh"',
        "last-modified": "Fri, 28 Aug 2026 12:39:21 GMT",
      },
    }),
  });
  try {
    const response = await worker.fetch(new Request(ipaUrl), env, runtime.ctx);
    assert.equal(response.status, 200);
    assert.deepEqual(new Uint8Array(await response.arrayBuffer()), payload);
    assert.equal(response.headers.get("x-sunland-cache"), "MISS");

    await runtime.finish();
    assert.equal(runtime.upstreamRequests.length, 1);
    assert.match(runtime.upstreamRequests[0].input, /releases\/download\/v1\.4\.2%2B31\/sunland-ai-1\.4\.2%2B31\.ipa/u);
    assert.equal(runtime.cachePuts.length, 1);
    assert.deepEqual(runtime.cachePuts[0].body, payload);
    assert.equal(runtime.cachePuts[0].response.headers.get("cache-control"), "public, max-age=31536000, immutable");
  } finally {
    await runtime.finish();
  }
});

test("download proxy serves cached ranges and preserves partial metadata", async () => {
  const runtime = installRuntime({
    cachedResponse(request) {
      assert.equal(request.headers.get("range"), "bytes=2-5");
      return new Response("ched", {
        status: 206,
        headers: {
          "content-length": "4",
          "content-range": "bytes 2-5/10",
        },
      });
    },
  });
  try {
    const response = await worker.fetch(
      new Request(ipaUrl, { headers: { Range: "bytes=2-5" } }),
      env,
      runtime.ctx,
    );

    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), "bytes 2-5/10");
    assert.equal(await response.text(), "ched");
    assert.equal(runtime.upstreamRequests.length, 0);
  } finally {
    await runtime.finish();
  }
});

test("download proxy forwards cold ranges without caching partial responses", async () => {
  const runtime = installRuntime({
    upstreamResponse(_input, init) {
      assert.equal(init.headers.get("range"), "bytes=0-3");
      assert.equal(init.headers.get("if-range"), '"asset-etag"');
      return new Response("IPA!", {
        status: 206,
        headers: {
          "content-length": "4",
          "content-range": "bytes 0-3/29198469",
          etag: '"asset-etag"',
        },
      });
    },
  });
  try {
    const response = await worker.fetch(
      new Request(ipaUrl, {
        headers: {
          Range: "bytes=0-3",
          "If-Range": '"asset-etag"',
        },
      }),
      env,
      runtime.ctx,
    );

    assert.equal(response.status, 206);
    assert.equal(response.headers.get("content-range"), "bytes 0-3/29198469");
    assert.equal(await response.text(), "IPA!");
    assert.equal(runtime.cacheMatches.length, 0);
    assert.equal(runtime.cachePuts.length, 0);
  } finally {
    await runtime.finish();
  }
});

test("download proxy answers HEAD with metadata and no body", async () => {
  const runtime = installRuntime({
    upstreamResponse(_input, init) {
      assert.equal(init.method, "HEAD");
      return new Response(null, {
        status: 200,
        headers: {
          "content-length": "29198469",
          etag: '"asset-etag"',
        },
      });
    },
  });
  try {
    const response = await worker.fetch(
      new Request(ipaUrl, { method: "HEAD" }),
      env,
      runtime.ctx,
    );

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-length"), "29198469");
    assert.equal(await response.text(), "");
  } finally {
    await runtime.finish();
  }
});

test("download proxy returns an uncached 502 when GitHub fails", async () => {
  const runtime = installRuntime({
    upstreamResponse: new Response("bad gateway", { status: 502 }),
  });
  try {
    const response = await worker.fetch(new Request(ipaUrl), env, runtime.ctx);

    assert.equal(response.status, 502);
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.equal(runtime.cachePuts.length, 0);
  } finally {
    await runtime.finish();
  }
});

test("download proxy emits Android metadata for APK assets", async () => {
  const apkUrl = `https://api.sunland.dev/v1/download/apk?v=${encodeURIComponent(version)}`;
  const runtime = installRuntime({
    upstreamResponse: new Response("APK!", {
      status: 200,
      headers: { "content-length": "4" },
    }),
  });
  try {
    const response = await worker.fetch(new Request(apkUrl), env, runtime.ctx);

    assert.equal(response.status, 200);
    assert.equal(response.headers.get("content-type"), "application/vnd.android.package-archive");
    assert.equal(response.headers.get("content-disposition"), `attachment; filename="sunland-ai-${version}.apk"`);
    assert.match(runtime.upstreamRequests[0].input, /sunland-ai-1\.4\.2%2B31\.apk$/u);
  } finally {
    await runtime.finish();
  }
});

test("download proxy preserves 304 and 416 without caching errors", async () => {
  for (const { status, headers } of [
    { status: 304, headers: { etag: '"asset-etag"' } },
    { status: 416, headers: { "content-range": "bytes */29198469" } },
  ]) {
    const runtime = installRuntime({
      upstreamResponse: new Response(null, { status, headers }),
    });
    try {
      const response = await worker.fetch(
        new Request(ipaUrl, { headers: { Range: "bytes=999999999-" } }),
        env,
        runtime.ctx,
      );
      assert.equal(response.status, status);
      assert.equal(response.headers.get("cache-control"), "no-store");
      assert.equal(runtime.cachePuts.length, 0);
    } finally {
      await runtime.finish();
    }
  }
});
