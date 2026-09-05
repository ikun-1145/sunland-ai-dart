const MAX_ADMIN_BODY_BYTES = 16 * 1024;
const MAX_PAGE_SIZE = 100;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export async function handleControlPlaneRequest(request, env, url) {
  if (url.pathname === "/healthz") {
    if (request.method !== "GET") return response({ error: "Method not allowed" }, 405, env);
    const version = env.CF_VERSION_METADATA
      ? {
          id: env.CF_VERSION_METADATA.id ?? null,
          tag: env.CF_VERSION_METADATA.tag ?? null,
          timestamp: env.CF_VERSION_METADATA.timestamp ?? null,
        }
      : null;
    return response({ service: "sunland-api", status: "ok", version }, 200, env);
  }

  if (url.pathname === "/v1/announcements") {
    if (request.method !== "GET") return response({ error: "Method not allowed" }, 405, env);
    const page = pageOptions(url);
    const result = await rpc(env, "sunland_public_announcements", {
      p_page: page.page,
      p_page_size: page.pageSize,
    });
    return result.ok
      ? response(result.payload, 200, env)
      : response({ error: "ANNOUNCEMENTS_UNAVAILABLE", message: "公告暂时不可用" }, 503, env);
  }

  if (!url.pathname.startsWith("/v1/admin/")) return null;

  const admin = await requireAdmin(request, env);
  if (!admin.ok) return response({ error: admin.error, message: admin.message }, admin.status, env);

  if (request.method === "GET") return handleAdminGet(url, env, admin.value);
  if (!["POST", "PATCH", "DELETE"].includes(request.method)) {
    return response({ error: "Method not allowed" }, 405, env);
  }
  return handleAdminMutation(request, url, env, admin.value);
}

async function handleAdminGet(url, env, admin) {
  const page = pageOptions(url);

  if (url.pathname === "/v1/admin/stats") {
    return rpcMappedResponse(env, "sunland_admin_stats", {}, mapStats);
  }
  if (url.pathname === "/v1/admin/pro/stats") {
    return rpcMappedResponse(env, "sunland_admin_pro_stats", {}, mapProStats);
  }
  if (url.pathname === "/v1/admin/pro/activations") {
    return rpcResponse(env, "sunland_admin_list_pro_activations", {
      p_query: normalizedQuery(url.searchParams.get("q")),
      p_page: page.page,
      p_page_size: page.pageSize,
    });
  }
  if (url.pathname === "/v1/admin/users") {
    const sort = url.searchParams.get("sort") || "created_at";
    const descending = url.searchParams.get("direction") !== "asc";
    return rpcMappedResponse(env, "sunland_admin_list_users", {
      p_query: normalizedQuery(url.searchParams.get("q")),
      p_page: page.page,
      p_page_size: page.pageSize,
      p_sort: sort,
      p_desc: descending,
    }, mapUserList);
  }
  if (url.pathname.startsWith("/v1/admin/users/")) {
    const userId = decodePathTail(url.pathname, "/v1/admin/users/");
    if (!userId) return response({ error: "VALIDATION_ERROR", message: "用户标识无效" }, 400, env);
    const result = await rpc(env, "sunland_admin_user_detail", { p_user_id: userId });
    if (!result.ok) return response({ error: "DATABASE_ERROR", message: "用户资料暂时不可用" }, 503, env);
    if (result.payload == null) return response({ error: "USER_NOT_FOUND", message: "用户不存在" }, 404, env);
    return response(mapUserDetail(result.payload), 200, env);
  }
  if (url.pathname === "/v1/admin/announcements") return listAnnouncements(env, page);
  if (url.pathname === "/v1/admin/logs") return listAuditLogs(env, page);
  if (url.pathname === "/v1/admin/system/status") return systemStatus(env);
  if (url.pathname === "/v1/admin/versions") return versions(env);

  return response({ error: "Not found" }, 404, env);
}

async function handleAdminMutation(request, url, env, admin) {
  const requiresBody =
    url.pathname === "/v1/admin/system/maintenance" ||
    url.pathname === "/v1/admin/announcements" ||
    (request.method === "PATCH" && url.pathname.startsWith("/v1/admin/announcements/"));
  const parsed = requiresBody
    ? await readJson(request, MAX_ADMIN_BODY_BYTES)
    : { ok: true, status: 200, value: {} };
  const body = parsed.value;

  if (!parsed.ok) {
    return mutationFailure(env, admin, "admin_request_rejected", "admin_api", url.pathname, "VALIDATION_ERROR", parsed.status);
  }

  if (request.method === "POST" && url.pathname === "/v1/admin/system/maintenance") {
    const enabled = body.enabled;
    const title = stringWithin(body.title, 1, 120);
    const message = stringWithin(body.message, 1, 1000);
    const estimatedEnd = optionalIsoTimestamp(body.estimatedEnd);
    if (typeof enabled !== "boolean" || !title || !message || estimatedEnd.invalid) {
      return mutationFailure(env, admin, "maintenance_updated", "app_config", "global", "VALIDATION_ERROR", 400);
    }
    return runMutation(env, admin, {
      action: enabled ? "maintenance_enabled" : "maintenance_disabled",
      targetType: "app_config",
      targetId: "global",
      rpcName: "sunland_admin_set_maintenance",
      rpcArgs: {
        p_admin_user_id: admin.authUserId,
        p_enabled: enabled,
        p_title: title,
        p_message: message,
        p_estimated_end: estimatedEnd.value,
      },
    });
  }

  const userBan = userBanPath(url.pathname);
  if (request.method === "POST" && userBan) {
    return runMutation(env, admin, {
      action: userBan.banned ? "user_banned" : "user_unbanned",
      targetType: "user_profile",
      targetId: userBan.userId,
      rpcName: "sunland_admin_set_user_ban",
      rpcArgs: {
        p_admin_user_id: admin.authUserId,
        p_user_id: userBan.userId,
        p_is_banned: userBan.banned,
      },
      mapPayload: mapUserBan,
    });
  }

  if (request.method === "POST" && url.pathname === "/v1/admin/announcements") {
    const input = announcementInput(body);
    if (!input) return mutationFailure(env, admin, "announcement_created", "announcement", null, "VALIDATION_ERROR", 400);
    return runMutation(env, admin, {
      action: "announcement_created",
      targetType: "announcement",
      targetId: null,
      rpcName: "sunland_admin_create_announcement",
      rpcArgs: { p_admin_user_id: admin.authUserId, ...input },
      mapPayload: mapAnnouncement,
    });
  }

  const announcementId = announcementPathId(url.pathname);
  if (!announcementId) return response({ error: "Not found" }, 404, env);

  if (request.method === "PATCH" && url.pathname === `/v1/admin/announcements/${announcementId}`) {
    const input = announcementInput(body);
    if (!input) return mutationFailure(env, admin, "announcement_updated", "announcement", announcementId, "VALIDATION_ERROR", 400);
    return runMutation(env, admin, {
      action: "announcement_updated",
      targetType: "announcement",
      targetId: announcementId,
      rpcName: "sunland_admin_update_announcement",
      rpcArgs: { p_admin_user_id: admin.authUserId, p_id: announcementId, ...input },
      mapPayload: mapAnnouncement,
    });
  }

  if (request.method === "POST" && url.pathname === `/v1/admin/announcements/${announcementId}/publish`) {
    return runMutation(env, admin, {
      action: "announcement_published",
      targetType: "announcement",
      targetId: announcementId,
      rpcName: "sunland_admin_set_announcement_active",
      rpcArgs: { p_admin_user_id: admin.authUserId, p_id: announcementId, p_active: true },
      mapPayload: mapAnnouncement,
    });
  }

  if (request.method === "POST" && url.pathname === `/v1/admin/announcements/${announcementId}/unpublish`) {
    return runMutation(env, admin, {
      action: "announcement_unpublished",
      targetType: "announcement",
      targetId: announcementId,
      rpcName: "sunland_admin_set_announcement_active",
      rpcArgs: { p_admin_user_id: admin.authUserId, p_id: announcementId, p_active: false },
      mapPayload: mapAnnouncement,
    });
  }

  if (request.method === "DELETE" && url.pathname === `/v1/admin/announcements/${announcementId}`) {
    return runMutation(env, admin, {
      action: "announcement_deleted",
      targetType: "announcement",
      targetId: announcementId,
      rpcName: "sunland_admin_delete_draft_announcement",
      rpcArgs: { p_admin_user_id: admin.authUserId, p_id: announcementId },
      status: 204,
    });
  }

  return response({ error: "Not found" }, 404, env);
}

async function requireAdmin(request, env) {
  const token = bearerToken(request.headers.get("Authorization"));
  const expectedAuthUserId = nonEmpty(env.ADMIN_AUTH_USER_ID);
  const expectedEmail = nonEmpty(env.ADMIN_EMAIL)?.toLowerCase();
  const projectUrl = supabaseProjectUrl(env);
  const serverKey = supabaseServerKey(env);
  if (!expectedAuthUserId || !expectedEmail || !projectUrl || !serverKey) {
    console.error(JSON.stringify({ event: "admin_config_missing" }));
    return { ok: false, status: 503, error: "ADMIN_UNAVAILABLE", message: "管理服务暂时不可用" };
  }
  if (!token) return { ok: false, status: 401, error: "UNAUTHORIZED", message: "需要管理员登录" };

  let authResponse;
  try {
    authResponse = await fetch(`${projectUrl}/auth/v1/user`, {
      headers: { apikey: serverKey, Authorization: `Bearer ${token}` },
      signal: AbortSignal.timeout(7000),
    });
  } catch {
    return { ok: false, status: 503, error: "AUTH_UNAVAILABLE", message: "身份服务暂时不可用" };
  }
  if (!authResponse.ok) return { ok: false, status: 401, error: "UNAUTHORIZED", message: "登录已失效" };

  const authUser = await authResponse.json().catch(() => null);
  const verifiedEmail = typeof authUser?.email === "string" ? authUser.email.toLowerCase() : null;
  if (
    authUser?.id !== expectedAuthUserId ||
    verifiedEmail !== expectedEmail ||
    !authUser?.email_confirmed_at
  ) {
    return { ok: false, status: 403, error: "ADMIN_FORBIDDEN", message: "该账号没有管理权限" };
  }

  const profileUrl = `${projectUrl}/rest/v1/user_profiles?email=eq.${encodeURIComponent(expectedEmail)}&select=user_id&limit=2`;
  let profileResponse;
  try {
    profileResponse = await fetch(profileUrl, { headers: serviceHeaders(serverKey), signal: AbortSignal.timeout(7000) });
  } catch {
    return { ok: false, status: 503, error: "PROFILE_UNAVAILABLE", message: "管理员资料暂时不可用" };
  }
  const profiles = profileResponse.ok ? await profileResponse.json().catch(() => null) : null;
  if (!Array.isArray(profiles) || profiles.length !== 1 || !nonEmpty(profiles[0]?.user_id)) {
    return { ok: false, status: 403, error: "ADMIN_FORBIDDEN", message: "该账号没有管理权限" };
  }

  return { ok: true, value: { authUserId: authUser.id, profileUserId: profiles[0].user_id, email: expectedEmail } };
}

async function runMutation(env, admin, spec) {
  const result = await rpc(env, spec.rpcName, spec.rpcArgs);
  if (result.ok) {
    if (spec.status === 204) return new Response(null, { status: 204, headers: headers(env) });
    return response(spec.mapPayload ? spec.mapPayload(result.payload) : result.payload, spec.status || 200, env);
  }
  const failure = classifyFailure(result);
  return mutationFailure(env, admin, spec.action, spec.targetType, spec.targetId, failure.code, failure.status);
}

async function mutationFailure(env, admin, action, targetType, targetId, resultCode, status) {
  const recorded = await recordFailure(env, admin, action, targetType, targetId, resultCode);
  if (!recorded) {
    console.error(JSON.stringify({ event: "admin_failure_audit_unavailable", action, result: resultCode }));
    return response({ error: "AUDIT_UNAVAILABLE", message: "操作失败，审计服务暂时不可用" }, 503, env);
  }
  return response({ error: resultCode, message: messageFor(resultCode) }, status, env);
}

async function recordFailure(env, admin, action, targetType, targetId, resultCode) {
  const result = await rpc(env, "sunland_admin_record_failed_action", {
    p_admin_user_id: admin.authUserId,
    p_action: action,
    p_target_type: targetType,
    p_target_id: targetId,
    p_result: resultCode,
    p_metadata: {},
  });
  return result.ok;
}

async function listAnnouncements(env, page) {
  const projectUrl = supabaseProjectUrl(env);
  const serverKey = supabaseServerKey(env);
  if (!projectUrl || !serverKey) return response({ error: "ADMIN_UNAVAILABLE" }, 503, env);
  const offset = (page.page - 1) * page.pageSize;
  const url = `${projectUrl}/rest/v1/announcements?select=id,title,content,is_active,published_at,starts_at,ends_at,created_at,updated_at&order=created_at.desc&offset=${offset}&limit=${page.pageSize}`;
  const result = await restJson(url, serviceHeaders(serverKey, { Prefer: "count=exact" }));
  if (!result.ok) return response({ error: "DATABASE_ERROR", message: "公告暂时不可用" }, 503, env);
  return response({
    items: result.payload.map(mapAnnouncement),
    total: contentRangeCount(result.contentRange),
    page: page.page,
    pageSize: page.pageSize,
  }, 200, env);
}

async function listAuditLogs(env, page) {
  const projectUrl = supabaseProjectUrl(env);
  const serverKey = supabaseServerKey(env);
  if (!projectUrl || !serverKey) return response({ error: "ADMIN_UNAVAILABLE" }, 503, env);
  const offset = (page.page - 1) * page.pageSize;
  const url = `${projectUrl}/rest/v1/admin_audit_logs?select=id,admin_user_id,action,target_type,target_id,success,result,metadata,created_at&order=created_at.desc&offset=${offset}&limit=${page.pageSize}`;
  const result = await restJson(url, serviceHeaders(serverKey, { Prefer: "count=exact" }));
  if (!result.ok) return response({ error: "DATABASE_ERROR", message: "日志暂时不可用" }, 503, env);
  return response({
    items: result.payload.map((row) => ({
      id: row.id,
      adminUserId: row.admin_user_id,
      action: row.action,
      targetType: row.target_type,
      targetId: row.target_id,
      success: row.success,
      result: row.result,
      metadata: row.metadata,
      createdAt: row.created_at,
    })),
    total: contentRangeCount(result.contentRange),
    page: page.page,
    pageSize: page.pageSize,
  }, 200, env);
}

async function systemStatus(env) {
  const projectUrl = supabaseProjectUrl(env);
  const serverKey = supabaseServerKey(env);
  const version = env.CF_VERSION_METADATA
    ? { id: env.CF_VERSION_METADATA.id ?? null, tag: env.CF_VERSION_METADATA.tag ?? null, timestamp: env.CF_VERSION_METADATA.timestamp ?? null }
    : null;
  const [supabaseResult, coreResult] = await Promise.all([
    projectUrl && serverKey
      ? restJson(`${projectUrl}/rest/v1/app_config?id=eq.global&select=maintenance_enabled,maintenance_title,maintenance_message,maintenance_estimated_end,updated_at`, serviceHeaders(serverKey))
      : Promise.resolve({ ok: false }),
    fetch("https://ai-core.sunland.dev/healthz", { signal: AbortSignal.timeout(7000) })
      .then((res) => ({ ok: res.ok }))
      .catch(() => ({ ok: false })),
  ]);
  const config = supabaseResult.ok && Array.isArray(supabaseResult.payload) ? supabaseResult.payload[0] : null;
  return response({
    worker: { ok: true, version },
    supabase: { ok: Boolean(config) },
    aiCore: { ok: coreResult.ok === true },
    aiProvider: { checked: false, status: "UNVERIFIED" },
    maintenance: config
      ? {
          enabled: config.maintenance_enabled === true,
          title: config.maintenance_title,
          message: config.maintenance_message,
          estimatedEnd: config.maintenance_estimated_end,
          updatedAt: config.updated_at,
        }
      : null,
  }, 200, env);
}

async function versions(env) {
  try {
    const release = await fetch("https://sunland.dev/update.json", { signal: AbortSignal.timeout(7000) });
    if (!release.ok) throw new Error("update unavailable");
    const update = await release.json();
    return response({
      android: {
        version: typeof update.version === "string" ? update.version : null,
        build: typeof update.build === "number" || typeof update.build === "string" ? update.build : null,
        force: update.force === true,
        releaseNotes: typeof update.desc === "string" ? update.desc : null,
      },
      ios: null,
    }, 200, env);
  } catch {
    return response({ error: "VERSIONS_UNAVAILABLE", message: "版本信息暂时不可用" }, 503, env);
  }
}

async function rpcResponse(env, name, args) {
  const result = await rpc(env, name, args);
  return result.ok
    ? response(result.payload, 200, env)
    : response({ error: "DATABASE_ERROR", message: "数据暂时不可用" }, 503, env);
}

async function rpcMappedResponse(env, name, args, map) {
  const result = await rpc(env, name, args);
  return result.ok
    ? response(map(result.payload), 200, env)
    : response({ error: "DATABASE_ERROR", message: "数据暂时不可用" }, 503, env);
}

async function rpc(env, name, args) {
  const projectUrl = supabaseProjectUrl(env);
  const serverKey = supabaseServerKey(env);
  if (!projectUrl || !serverKey) return { ok: false, status: 503, payload: null };
  return restJson(`${projectUrl}/rest/v1/rpc/${name}`, serviceHeaders(serverKey, { "Content-Type": "application/json" }), {
    method: "POST",
    body: JSON.stringify(args),
  });
}

async function restJson(url, requestHeaders, init = {}) {
  try {
    const res = await fetch(url, { ...init, headers: requestHeaders, signal: AbortSignal.timeout(7000) });
    const payload = await res.json().catch(() => null);
    return { ok: res.ok, status: res.status, payload, contentRange: res.headers.get("content-range") };
  } catch {
    return { ok: false, status: 503, payload: null, contentRange: null };
  }
}

function serviceHeaders(serverKey, extra = {}) {
  return {
    apikey: serverKey,
    ...(serverKey.startsWith("sb_secret_") ? {} : { Authorization: `Bearer ${serverKey}` }),
    ...extra,
  };
}

function supabaseProjectUrl(env) {
  return nonEmpty(env.SUPABASE_PROJECT_URL) || nonEmpty(env.SUPABASE_URL);
}

function supabaseServerKey(env) {
  return nonEmpty(env.SUPABASE_SECRET_KEY) || nonEmpty(env.SUPABASE_SERVICE_ROLE_KEY);
}

function announcementInput(body) {
  const title = stringWithin(body.title, 1, 120);
  const content = stringWithin(body.content, 1, 10000);
  const startsAt = optionalIsoTimestamp(body.startsAt);
  const endsAt = optionalIsoTimestamp(body.endsAt);
  if (!title || !content || startsAt.invalid || endsAt.invalid) return null;
  if (startsAt.value && endsAt.value && Date.parse(endsAt.value) <= Date.parse(startsAt.value)) return null;
  return {
    p_title: title,
    p_content: content,
    p_starts_at: startsAt.value,
    p_ends_at: endsAt.value,
  };
}

function mapAnnouncement(row) {
  if (!row || typeof row !== "object") return row;
  return {
    id: row.id,
    title: row.title,
    content: row.content,
    isActive: row.is_active,
    publishedAt: row.published_at,
    startsAt: row.starts_at,
    endsAt: row.ends_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function mapStats(payload) {
  if (!payload?.users || !payload?.pro) return payload;
  return {
    totalUsers: payload.users.total,
    currentProUsers: payload.pro.total,
    freeUsers: payload.pro.standard,
    newUsersToday: payload.users.today,
    newUsers7d: payload.users.last7Days,
    newUsers30d: payload.users.last30Days,
    newProToday: payload.pro.today,
    newPro7d: payload.pro.last7Days,
    newPro30d: payload.pro.last30Days,
    userGrowth30d: payload.users.trend,
    usageAvailable: false,
  };
}

function mapProStats(payload) {
  if (!payload || Object.hasOwn(payload, "currentProUsers")) return payload;
  return {
    currentProUsers: payload.total,
    proRatio: payload.ratio,
    newProToday: payload.today,
    newPro7d: payload.last7Days,
    newPro30d: payload.last30Days,
  };
}

function mapUserList(payload) {
  if (!payload?.items || !Array.isArray(payload.items)) return payload;
  return {
    ...payload,
    items: payload.items.map((row) => ({
      userId: row.userId,
      nickname: row.name,
      email: row.email,
      avatarUrl: row.avatarUrl,
      pro: row.isPro === true,
      banned: row.isBanned === true,
      createdAt: row.createdAt,
      conversationCount: row.conversationCount ?? 0,
      lastActiveAt: row.lastActiveAt ?? null,
      messageCount: null,
    })),
  };
}

function mapUserDetail(row) {
  if (!row || typeof row !== "object") return row;
  return {
    userId: row.userId,
    nickname: row.name,
    email: row.email,
    avatarUrl: row.avatarUrl,
    pro: row.isPro === true,
    banned: row.isBanned === true,
    createdAt: row.createdAt,
    conversationCount: row.conversationCount ?? 0,
    userMessageCount: row.userMessageCount ?? 0,
    assistantMessageCount: row.assistantMessageCount ?? 0,
    recentActivityAt: row.lastActiveAt ?? null,
    recentModel: row.recentModel ?? null,
    proActivatedAt: row.proActivatedAt ?? null,
    proSource: row.proSource ?? null,
    orderId: row.orderId ?? null,
  };
}

function mapUserBan(row) {
  if (!row || typeof row !== "object") return row;
  return {
    userId: row.userId,
    banned: row.isBanned === true,
  };
}

function classifyFailure(result) {
  const message = typeof result.payload?.message === "string" ? result.payload.message : "";
  if (message.includes("NOT_FOUND")) return { code: "NOT_FOUND", status: 404 };
  if (message.includes("WAS_PUBLISHED") || message.includes("ACTIVE")) return { code: "CONFLICT", status: 409 };
  if (result.status >= 400 && result.status < 500) return { code: "VALIDATION_ERROR", status: 400 };
  return { code: "DATABASE_ERROR", status: 503 };
}

function messageFor(code) {
  return {
    VALIDATION_ERROR: "请求参数无效",
    NOT_FOUND: "目标不存在",
    CONFLICT: "当前状态不允许此操作",
    DATABASE_ERROR: "操作暂时不可用",
  }[code] || "操作失败";
}

function pageOptions(url) {
  const page = Number.parseInt(url.searchParams.get("page") || "1", 10);
  const pageSize = Number.parseInt(url.searchParams.get("pageSize") || "20", 10);
  return {
    page: Number.isFinite(page) ? Math.max(1, page) : 1,
    pageSize: Number.isFinite(pageSize) ? Math.min(MAX_PAGE_SIZE, Math.max(1, pageSize)) : 20,
  };
}

function contentRangeCount(value) {
  const match = /\/(\d+)$/.exec(value || "");
  return match ? Number(match[1]) : 0;
}

function announcementPathId(pathname) {
  const match = /^\/v1\/admin\/announcements\/([^/]+)(?:\/(?:publish|unpublish))?$/.exec(pathname);
  const id = match ? decodeURIComponent(match[1]) : null;
  return id && UUID_PATTERN.test(id) ? id : null;
}

function userBanPath(pathname) {
  const match = /^\/v1\/admin\/users\/([^/]+)\/(ban|unban)$/.exec(pathname);
  if (!match) return null;
  let userId;
  try {
    userId = decodeURIComponent(match[1]);
  } catch {
    return null;
  }
  if (!userId || userId.length > 160 || /[\u0000-\u001f]/.test(userId)) return null;
  return { userId, banned: match[2] === "ban" };
}

function decodePathTail(pathname, prefix) {
  const value = pathname.slice(prefix.length);
  if (!value || value.includes("/")) return null;
  try {
    return decodeURIComponent(value);
  } catch {
    return null;
  }
}

function normalizedQuery(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 && trimmed.length <= 120 ? trimmed : null;
}

function stringWithin(value, min, max) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length >= min && trimmed.length <= max ? trimmed : null;
}

function optionalIsoTimestamp(value) {
  if (value == null || value === "") return { value: null, invalid: false };
  if (typeof value !== "string" || Number.isNaN(Date.parse(value))) return { value: null, invalid: true };
  return { value: new Date(value).toISOString(), invalid: false };
}

function bearerToken(value) {
  const match = /^Bearer\s+(.+)$/i.exec(value || "");
  return match ? match[1].trim() : null;
}

function nonEmpty(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null;
}

async function readJson(request, maxBytes) {
  const length = Number.parseInt(request.headers.get("content-length") || "0", 10);
  if (Number.isFinite(length) && length > maxBytes) return { ok: false, status: 413, value: null };
  if (!request.body) return { ok: false, status: 400, value: null };
  const reader = request.body.getReader();
  const chunks = [];
  let bytes = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > maxBytes) return { ok: false, status: 413, value: null };
      chunks.push(value);
    }
    const text = new TextDecoder().decode(concatChunks(chunks, bytes));
    const value = JSON.parse(text);
    return value && typeof value === "object" && !Array.isArray(value)
      ? { ok: true, status: 200, value }
      : { ok: false, status: 400, value: null };
  } catch {
    return { ok: false, status: 400, value: null };
  } finally {
    reader.releaseLock();
  }
}

function concatChunks(chunks, length) {
  const output = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    output.set(chunk, offset);
    offset += chunk.length;
  }
  return output;
}

function response(data, status, env) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers(env) },
  });
}

function headers(env) {
  return {
    "Access-Control-Allow-Origin": env.ALLOWED_ORIGIN || "https://sunland.dev",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Access-Control-Allow-Methods": "GET, HEAD, POST, PATCH, DELETE, OPTIONS",
  };
}
