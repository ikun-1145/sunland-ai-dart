import { createClient } from "https://esm.sh/@supabase/supabase-js@2.57.4";
import { FURRY_EVENT_SOURCE } from "../_shared/furry_event_contract.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const SELECT_FIELDS = [
  "source_id", "name", "full_name", "start_at", "end_at", "province",
  "city", "address", "venue", "cover", "status", "source_state",
  "source_state_text", "source_url", "detail", "organization", "updated_at",
].join(",");

type SearchRequest = {
  query?: string;
  city?: string;
  month?: number;
  year?: number;
  include_inactive?: boolean;
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json; charset=utf-8" },
  });
}

function normalizeInteger(value: unknown, min: number, max: number): number | null {
  if (value == null || value === "") return null;
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= min && parsed <= max ? parsed : null;
}

function shanghaiToday(): { year: number; month: number; day: number } {
  const shifted = new Date(Date.now() + 8 * 60 * 60 * 1000);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
  };
}

function isoDate(year: number, month: number, day = 1): string {
  const normalized = new Date(Date.UTC(year, month - 1, day));
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${normalized.getUTCFullYear()}-${pad(normalized.getUTCMonth() + 1)}-${pad(normalized.getUTCDate())}T00:00:00+08:00`;
}

function searchRange(month: number | null, year: number | null) {
  const today = shanghaiToday();
  if (month !== null) {
    const resolvedYear = year ?? (month < today.month ? today.year + 1 : today.year);
    return { start: isoDate(resolvedYear, month), end: isoDate(resolvedYear, month + 1) };
  }
  if (year !== null) {
    return { start: isoDate(year, 1), end: isoDate(year + 1, 1) };
  }
  return { start: isoDate(today.year, today.month, today.day), end: null };
}

function safeLocation(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.replace(/[,%()*"']/g, " ").replace(/\s+/g, " ").trim();
  return text ? text.slice(0, 64) : null;
}

function withAliases(row: Record<string, unknown>) {
  return {
    ...row,
    startAt: row.start_at ?? null,
    endAt: row.end_at ?? null,
    coverUrl: row.cover ?? null,
    sourceUrl: row.source_url ?? null,
  };
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "METHOD_NOT_ALLOWED", message: "Only POST is supported" }, 405);
  }
  if (!request.headers.get("Authorization")?.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHORIZED", message: "A valid bearer token is required" }, 401);
  }

  let payload: SearchRequest = {};
  try {
    const text = await request.text();
    payload = text.trim() ? JSON.parse(text) : {};
  } catch {
    return jsonResponse({ error: "INVALID_REQUEST", message: "Request body must be valid JSON" }, 400);
  }
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return jsonResponse({ error: "INVALID_REQUEST", message: "Request body must be an object" }, 400);
  }

  const city = safeLocation(payload.city);
  const month = normalizeInteger(payload.month, 1, 12);
  const year = normalizeInteger(payload.year, 2000, 2100);
  if (payload.month != null && month === null) {
    return jsonResponse({ error: "INVALID_REQUEST", message: "month must be between 1 and 12" }, 400);
  }
  if (payload.year != null && year === null) {
    return jsonResponse({ error: "INVALID_REQUEST", message: "year must be between 2000 and 2100" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "SERVICE_UNAVAILABLE", message: "Database configuration is unavailable" }, 503);
  }
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const range = searchRange(month, year);
    let query = admin
      .from("furry_events")
      .select(SELECT_FIELDS)
      .eq("source", FURRY_EVENT_SOURCE)
      .gte("start_at", range.start);
    if (payload.include_inactive !== true) query = query.eq("is_active", true);
    if (city) {
      query = query.or(`address.ilike.*${city}*,province.ilike.*${city}*,city.ilike.*${city}*`);
    }
    if (range.end) query = query.lt("start_at", range.end);

    const { data, error } = await query.order("start_at", { ascending: true });
    if (error) throw error;
    const rows = (data ?? []) as unknown as Record<string, unknown>[];
    const events = rows.map(withAliases);
    return jsonResponse({
      events,
      total: events.length,
      cached: false,
      cacheKey: null,
    });
  } catch (error) {
    console.error(JSON.stringify({
      level: "error",
      code: "FURRY_EVENT_SEARCH_FAILED",
      message: error instanceof Error ? error.message : String(error),
    }));
    return jsonResponse({
      error: "FURRY_EVENT_SEARCH_FAILED",
      message: "Furry events could not be queried",
      details: {},
    }, 500);
  }
});
