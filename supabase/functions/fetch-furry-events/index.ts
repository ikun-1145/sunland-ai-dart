import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import {
  ContractError,
  FURRY_EVENT_SOURCE,
  constantTimeEqual,
  parseAllowEmpty,
  shouldRejectEmptySnapshot,
  validateEmptyOverride,
  validateWorkerPayload,
} from "../_shared/furry_event_contract.ts";

const WORKER_URL = "https://sunland-data-worker.liuxizekali.workers.dev";
const REQUEST_TIMEOUT_MS = 20_000;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-function-secret, x-sync-trigger",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function emptySnapshotResponse(active: number): Response {
  return jsonResponse({
    success: false,
    error: "EMPTY_SNAPSHOT_REJECTED",
    message: "An empty snapshot cannot replace existing active events",
    details: { active },
  }, 409);
}

async function readJsonBody(request: Request): Promise<unknown> {
  const text = await request.text();
  if (!text.trim()) return {};
  try {
    return JSON.parse(text);
  } catch {
    throw new ContractError("INVALID_REQUEST", "Request body must be valid JSON");
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ success: false, error: "METHOD_NOT_ALLOWED", message: "Only POST is supported" }, 405);
  }
  if (!request.headers.get("Authorization")?.startsWith("Bearer ")) {
    return jsonResponse({ success: false, error: "UNAUTHORIZED", message: "A valid bearer token is required" }, 401);
  }

  const expectedSecret = Deno.env.get("FUNCTION_SECRET") ?? "";
  const suppliedSecret = request.headers.get("x-function-secret") ?? "";
  if (!expectedSecret || !constantTimeEqual(suppliedSecret, expectedSecret)) {
    return jsonResponse({ success: false, error: "INVALID_FUNCTION_SECRET", message: "Function secret validation failed" }, 403);
  }

  try {
    const allowEmpty = parseAllowEmpty(await readJsonBody(request));
    const trigger = (request.headers.get("x-sync-trigger") ?? "").trim().toLowerCase();
    validateEmptyOverride(allowEmpty, trigger);

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS);
    let workerResponse: Response;
    try {
      workerResponse = await fetch(WORKER_URL, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        signal: controller.signal,
      });
    } finally {
      clearTimeout(timer);
    }
    if (!workerResponse.ok) {
      const details = await workerResponse.json().catch(() => ({}));
      return jsonResponse({
        success: false,
        error: "WORKER_REQUEST_FAILED",
        message: `Worker returned HTTP ${workerResponse.status}`,
        details,
      }, 502);
    }
    const events = validateWorkerPayload(await workerResponse.json());

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error("Supabase service configuration is unavailable");
    }
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { count: activeCount, error: activeError } = await admin
      .from("furry_events")
      .select("id", { count: "exact", head: true })
      .eq("source", FURRY_EVENT_SOURCE)
      .eq("is_active", true);
    if (activeError) throw activeError;
    if (shouldRejectEmptySnapshot(events.length, activeCount ?? 0, allowEmpty)) {
      return emptySnapshotResponse(activeCount ?? 0);
    }

    const syncedAt = new Date().toISOString();
    const { data, error } = await admin.rpc("sync_furry_events", {
      events,
      synced_at: syncedAt,
      allow_empty: allowEmpty,
    });
    if (error) {
      if (`${error.message} ${error.details ?? ""}`.includes("EMPTY_SNAPSHOT_REJECTED")) {
        return emptySnapshotResponse(activeCount ?? 0);
      }
      throw error;
    }
    const result = Array.isArray(data) ? data[0] : data;
    if (!result || typeof result !== "object") {
      throw new Error("sync_furry_events returned an invalid result");
    }
    return jsonResponse({
      success: true,
      fetched: events.length,
      upserted: Number(result.upserted ?? 0),
      deactivated: Number(result.deactivated ?? 0),
      active: Number(result.active ?? 0),
      inactive: Number(result.inactive ?? 0),
      errors: [],
    });
  } catch (error) {
    if (error instanceof ContractError) {
      const isForbidden = error.code === "SCHEDULED_EMPTY_OVERRIDE_FORBIDDEN"
        || error.code === "ALLOW_EMPTY_REQUIRES_MANUAL_TRIGGER";
      return jsonResponse({
        success: false,
        error: error.code,
        message: error.message,
        details: error.details,
      }, isForbidden ? 403 : error.code === "INVALID_REQUEST" ? 400 : 502);
    }
    console.error(JSON.stringify({
      level: "error",
      code: "FURRY_EVENT_SYNC_FAILED",
      message: error instanceof Error ? error.message : String(error),
    }));
    return jsonResponse({
      success: false,
      error: "FURRY_EVENT_SYNC_FAILED",
      message: "The furry event snapshot could not be synchronized",
      details: {},
    }, 500);
  }
});
