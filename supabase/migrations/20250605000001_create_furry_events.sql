-- furry_events: 缓存 furrycons.cn 爬取结果（24h TTL）
CREATE TABLE IF NOT EXISTS public.furry_events (
  id           BIGSERIAL PRIMARY KEY,
  cache_key    TEXT        NOT NULL,
  cached_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  name         TEXT        NOT NULL,
  start_at     TEXT        NOT NULL,
  end_at       TEXT        NOT NULL,
  city         TEXT        NOT NULL,
  venue        TEXT        NOT NULL,
  cover_url    TEXT,
  source_url   TEXT,

  weather_date DATE,
  weather_code INT,
  temp_max     NUMERIC(5,1),
  temp_min     NUMERIC(5,1),
  precip_mm    NUMERIC(6,1),

  ctrip_url    TEXT,
  meituan_url  TEXT,

  raw_json     JSONB
);

CREATE INDEX IF NOT EXISTS idx_furry_events_cache_key ON public.furry_events (cache_key);
CREATE INDEX IF NOT EXISTS idx_furry_events_city      ON public.furry_events (city);
CREATE INDEX IF NOT EXISTS idx_furry_events_cached_at ON public.furry_events (cached_at DESC);

ALTER TABLE public.furry_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "furry_events_select_authenticated"
  ON public.furry_events FOR SELECT TO authenticated USING (true);
