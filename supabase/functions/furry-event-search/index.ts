import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// ── 城市坐标表（Open-Meteo，可按需扩充）──────────────────────────────────
const CITY_COORDS: Record<string, { lat: number; lon: number }> = {
  "北京":   { lat: 39.9042,  lon: 116.4074 },
  "上海":   { lat: 31.2304,  lon: 121.4737 },
  "广州":   { lat: 23.1291,  lon: 113.2644 },
  "深圳":   { lat: 22.5431,  lon: 114.0579 },
  "成都":   { lat: 30.5728,  lon: 104.0668 },
  "杭州":   { lat: 30.2741,  lon: 120.1551 },
  "武汉":   { lat: 30.5928,  lon: 114.3055 },
  "南京":   { lat: 32.0603,  lon: 118.7969 },
  "西安":   { lat: 34.3416,  lon: 108.9398 },
  "重庆":   { lat: 29.5630,  lon: 106.5516 },
  "天津":   { lat: 39.0842,  lon: 117.2010 },
  "长沙":   { lat: 28.2282,  lon: 112.9388 },
  "哈尔滨": { lat: 45.8038,  lon: 126.5349 },
  "昆明":   { lat: 25.0453,  lon: 102.7097 },
  "福州":   { lat: 26.0745,  lon: 119.2965 },
  "厦门":   { lat: 24.4798,  lon: 118.0894 },
  "郑州":   { lat: 34.7466,  lon: 113.6254 },
  "苏州":   { lat: 31.2990,  lon: 120.5853 },
  "大连":   { lat: 38.9140,  lon: 121.6147 },
  "青岛":   { lat: 36.0671,  lon: 120.3826 },
};

// ── WMO 天气码 → 中文标签 ────────────────────────────────────────────────
function wmoLabel(code: number | null): string {
  if (code === null) return "未知";
  if (code === 0) return "晴";
  if (code <= 3)  return "多云";
  if (code <= 9)  return "雾";
  if (code <= 49) return "大雾";
  if (code <= 59) return "毛毛雨";
  if (code <= 69) return "雨";
  if (code <= 79) return "雪";
  if (code <= 84) return "阵雨";
  if (code <= 90) return "阵雪";
  return "雷暴";
}

// ── 日期工具 ──────────────────────────────────────────────────────────────
function todayCacheKey(): string {
  const d = new Date();
  const y = d.getUTCFullYear();
  const m = String(d.getUTCMonth() + 1).padStart(2, "0");
  const day = String(d.getUTCDate()).padStart(2, "0");
  return `list_${y}_${m}_${day}`;
}

function daysFromNow(iso: string): number {
  return Math.round((new Date(iso).getTime() - Date.now()) / 86_400_000);
}

function addDays(iso: string, n: number): string {
  return new Date(new Date(iso).getTime() + n * 86_400_000)
    .toISOString().slice(0, 10);
}

// ── 爬取 furrycons.cn 活动列表 ────────────────────────────────────────────
interface ScrapedEvent {
  name: string; startAt: string; endAt: string;
  city: string; venue: string; coverUrl: string; sourceUrl: string;
  rawJson: Record<string, unknown>;
}

async function scrapeFurryconsEvents(): Promise<ScrapedEvent[]> {
  const CANDIDATES = [
    "https://www.furrycons.cn/events",
    "https://www.furrycons.cn/conventions",
    "https://www.furrycons.cn/",
  ];

  let html = "";
  let baseUrl = "";

  for (const url of CANDIDATES) {
    try {
      const r = await fetch(url, {
        headers: {
          "User-Agent": "Mozilla/5.0 (compatible; SunlandAI/1.0)",
          "Accept": "text/html",
          "Accept-Language": "zh-CN,zh;q=0.9",
        },
        signal: AbortSignal.timeout(12_000),
      });
      if (!r.ok) continue;
      const text = await r.text();
      if (
        text.includes("__NEXT_DATA__") &&
        (text.includes('"events"') || text.includes('"conventions"'))
      ) {
        html = text;
        baseUrl = url;
        break;
      }
    } catch { /* 尝试下一个 URL */ }
  }

  if (!html) throw new Error("furrycons.cn: 无法获取活动列表页面");

  const match = html.match(/<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/);
  if (!match) throw new Error("furrycons.cn: 未找到 __NEXT_DATA__");

  const nextData = JSON.parse(match[1]) as any;
  const pp = nextData?.props?.pageProps ?? {};
  const rawList: any[] = pp.events ?? pp.conventions ?? pp.data?.events ?? [];

  if (!Array.isArray(rawList) || rawList.length === 0) {
    throw new Error("furrycons.cn: pageProps 中未找到 events 数组");
  }

  return rawList.map((raw: any) => {
    const name    = raw.name ?? raw.title ?? "未知活动";
    const startAt = raw.startAt ?? raw.start_at ?? raw.startTime ?? "";
    const endAt   = raw.endAt   ?? raw.end_at   ?? raw.endTime   ?? "";
    const city    = raw.region?.name ?? raw.city?.name ?? raw.cityName ?? "";
    const venue   = raw.address ?? raw.venue ?? raw.location?.address ?? "";
    const thumb   = raw.thumbnail ?? raw.cover ?? raw.coverImage ?? "";
    const coverUrl = thumb
      ? `https://www.furrycons.cn/${thumb.replace(/^\//, "")}`
      : "";
    const slug = raw.slug ?? raw.id ?? "";
    const sourceUrl = slug
      ? `https://www.furrycons.cn/events/${slug}`
      : baseUrl;
    return { name, startAt, endAt, city, venue, coverUrl, sourceUrl, rawJson: raw };
  });
}

// ── Open-Meteo 天气（免费，无需 API Key，支持 16 天预报）────────────────
interface WeatherData {
  date: string; code: number; label: string;
  tempMax: number; tempMin: number; precipMm: number;
}

async function fetchWeather(city: string, targetDate: string): Promise<WeatherData | null> {
  const coords = CITY_COORDS[city];
  if (!coords) return null;
  const days = daysFromNow(targetDate);
  if (days < 0 || days > 15) return null;

  const params = new URLSearchParams({
    latitude:      String(coords.lat),
    longitude:     String(coords.lon),
    daily:         "temperature_2m_max,temperature_2m_min,weathercode,precipitation_sum",
    timezone:      "Asia/Shanghai",
    forecast_days: "16",
  });

  try {
    const r = await fetch(`https://api.open-meteo.com/v1/forecast?${params}`,
      { signal: AbortSignal.timeout(8_000) });
    if (!r.ok) return null;
    const data = await r.json() as any;
    const daily = data.daily;
    const idx = (daily?.time as string[] ?? []).indexOf(targetDate);
    if (idx === -1) return null;
    const code = daily.weathercode?.[idx] ?? 0;
    return {
      date:     targetDate,
      code,
      label:    wmoLabel(code),
      tempMax:  daily.temperature_2m_max?.[idx]  ?? 0,
      tempMin:  daily.temperature_2m_min?.[idx]  ?? 0,
      precipMm: daily.precipitation_sum?.[idx]   ?? 0,
    };
  } catch { return null; }
}

// ── 酒店搜索链接 ─────────────────────────────────────────────────────────
function hotelUrls(
  city: string, venue: string, checkin: string, checkout: string
) {
  const kw     = encodeURIComponent(`${city} ${venue}`);
  const cityKw = encodeURIComponent(`${city} 附近酒店`);
  return {
    ctripUrl:   `https://hotels.ctrip.com/hotels/list?keyword=${kw}&checkin=${checkin}&checkout=${checkout}`,
    meituanUrl: `https://i.meituan.com/awp/h5/hotel/search/search.html?keyword=${cityKw}&checkin=${checkin}&checkout=${checkout}`,
  };
}

// ── 主处理函数 ────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  const supabaseAdmin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );

  const supabaseUser = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false },
    }
  );

  const { data: { user }, error: authErr } = await supabaseUser.auth.getUser();
  if (authErr || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  let payload: { query?: string; city?: string; year?: number; month?: number } = {};
  try { payload = await req.json(); } catch { /* 空 body 合法 */ }

  const { city, year, month } = payload;

  try {
    const cacheKey = todayCacheKey();
    const cutoff   = new Date(Date.now() - 86_400_000).toISOString();

    const { data: cached } = await supabaseAdmin
      .from("furry_events")
      .select("*")
      .eq("cache_key", cacheKey)
      .gte("cached_at", cutoff)
      .order("start_at", { ascending: true });

    let events: any[] = [];
    let fromCache = false;

    if (cached && cached.length > 0) {
      events    = cached;
      fromCache = true;
    } else {
      const scraped = await scrapeFurryconsEvents();

      await supabaseAdmin.from("furry_events").delete().eq("cache_key", cacheKey);

      // 并行抓取天气，整体耗时约为单次请求而非累加，避免函数超时
      const rows: Record<string, unknown>[] = await Promise.all(
        scraped.map(async (ev) => {
          const startDate = ev.startAt?.slice(0, 10) ?? null;
          const endDate   = ev.endAt?.slice(0, 10) ?? startDate;

          const weather = (startDate && ev.city)
            ? await fetchWeather(ev.city, startDate)
            : null;

          const checkout = endDate
            ? addDays(endDate, 1)
            : (startDate ? addDays(startDate, 1) : "");

          const hotels = (startDate && ev.city)
            ? hotelUrls(ev.city, ev.venue, startDate, checkout)
            : { ctripUrl: null, meituanUrl: null };

          return {
            cache_key:    cacheKey,
            name:         ev.name,
            start_at:     ev.startAt,
            end_at:       ev.endAt,
            city:         ev.city,
            venue:        ev.venue,
            cover_url:    ev.coverUrl  || null,
            source_url:   ev.sourceUrl || null,
            weather_date: weather?.date    ?? null,
            weather_code: weather?.code    ?? null,
            temp_max:     weather?.tempMax ?? null,
            temp_min:     weather?.tempMin ?? null,
            precip_mm:    weather?.precipMm ?? null,
            ctrip_url:    hotels.ctripUrl,
            meituan_url:  hotels.meituanUrl,
            raw_json:     ev.rawJson,
          };
        })
      );

      if (rows.length > 0) {
        const { error: insErr } = await supabaseAdmin.from("furry_events").insert(rows);
        if (insErr) console.error("DB insert error:", insErr.message);
      }

      const { data: fresh } = await supabaseAdmin
        .from("furry_events")
        .select("*")
        .eq("cache_key", cacheKey)
        .order("start_at", { ascending: true });

      // 若写入或重查失败导致 fresh 为空，回退到内存中已富化的数据，
      // 保证本次仍能返回结果（内存值为真实数字，亦避免数据库往返）
      events = (fresh && fresh.length > 0) ? fresh : rows;
    }

    // 去重：防止并发冷缓存或删除失败导致同一活动重复
    const seen = new Set<string>();
    events = events.filter((e: any) => {
      const k = `${e.name}|${e.start_at}`;
      if (seen.has(k)) return false;
      seen.add(k);
      return true;
    });

    // 过滤
    let filtered = events;
    if (city) {
      filtered = filtered.filter((e: any) =>
        e.city && (e.city.includes(city) || city.includes(e.city))
      );
    }
    if (year || month) {
      filtered = filtered.filter((e: any) => {
        if (!e.start_at) return false;
        const d = new Date(e.start_at);
        if (isNaN(d.getTime())) return false;
        // 转换到北京时间（UTC+8，无夏令时）再取日历字段，
        // 避免 +08:00 活动在月/年边界被错误分桶
        const bj = new Date(d.getTime() + 8 * 3600 * 1000);
        if (year  && bj.getUTCFullYear()  !== year)  return false;
        if (month && bj.getUTCMonth() + 1 !== month) return false;
        return true;
      });
    }

    const responseEvents = filtered.map((e: any) => ({
      name:      e.name,
      startAt:   e.start_at,
      endAt:     e.end_at,
      city:      e.city,
      venue:     e.venue,
      coverUrl:  e.cover_url,
      sourceUrl: e.source_url,
      weather:   e.weather_code !== null ? {
        date:     e.weather_date,
        code:     e.weather_code,
        label:    wmoLabel(e.weather_code),
        tempMax:  e.temp_max,
        tempMin:  e.temp_min,
        precipMm: e.precip_mm,
      } : null,
      hotels: {
        ctripUrl:   e.ctrip_url,
        meituanUrl: e.meituan_url,
      },
    }));

    return new Response(
      JSON.stringify({
        events:   responseEvents,
        total:    responseEvents.length,
        cached:   fromCache,
        cacheKey,
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : String(err);
    console.error("furry-event-search error:", msg);
    return new Response(
      JSON.stringify({ error: msg, events: [], total: 0, cached: false }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
