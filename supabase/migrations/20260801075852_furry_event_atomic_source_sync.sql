alter table public.furry_events
  add column if not exists source_id text,
  add column if not exists full_name text,
  add column if not exists province text,
  add column if not exists organization text,
  add column if not exists detail text,
  add column if not exists source_state integer,
  add column if not exists source_state_text text,
  add column if not exists is_active boolean not null default true,
  add column if not exists last_seen_at timestamptz,
  add column if not exists source_path text,
  add column if not exists cover text,
  add column if not exists status text,
  add column if not exists source_url text,
  add column if not exists updated_at text;

-- source is deliberately backfilled before its default is installed. Existing
-- rows must never be mistaken for data produced by the new upstream.
alter table public.furry_events
  add column if not exists source text;

update public.furry_events
set source = 'legacy'
where source is null;

alter table public.furry_events
  alter column source set default 'furfantasia_event_data';

alter table public.furry_events
  alter column source set not null;

create index if not exists furry_events_source_id_idx
  on public.furry_events(source_id)
  where source_id is not null;

create index if not exists furry_events_source_path_idx
  on public.furry_events(source_path)
  where source_path is not null;

create index if not exists furry_events_active_source_idx
  on public.furry_events(source, is_active);

create or replace function public.sync_furry_events(
  events jsonb,
  synced_at timestamptz,
  allow_empty boolean default false
)
returns table (
  upserted bigint,
  deactivated bigint,
  active bigint,
  inactive bigint
)
language plpgsql
security invoker
set search_path = ''
as $$
declare
  source_name constant text := 'furfantasia_event_data';
  event_count integer;
  current_active bigint;
  upsert_count bigint := 0;
  deactivate_count bigint := 0;
  active_count bigint := 0;
  inactive_count bigint := 0;
begin
  if events is null or jsonb_typeof(events) <> 'array' then
    raise exception using
      errcode = '22023',
      message = 'INVALID_EVENTS_PAYLOAD',
      detail = 'events must be a JSON array';
  end if;
  if synced_at is null then
    raise exception using
      errcode = '22023',
      message = 'INVALID_SYNCED_AT',
      detail = 'synced_at is required';
  end if;

  event_count := jsonb_array_length(events);

  if exists (
    select 1
    from jsonb_array_elements(events) as item(value)
    where jsonb_typeof(item.value) <> 'object'
  ) then
    raise exception using
      errcode = '22023',
      message = 'INVALID_EVENT_RECORD',
      detail = 'Every event must be a JSON object';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(events) as item(value)
    where not item.value ?& array[
      'source_id', 'name', 'full_name', 'start_at', 'end_at',
      'province', 'city', 'address', 'venue', 'cover', 'status',
      'source_state', 'source_state_text', 'source_url', 'source_path',
      'detail', 'organization', 'updated_at'
    ]
  ) then
    raise exception using
      errcode = '22023',
      message = 'INVALID_EVENT_RECORD',
      detail = 'One or more required contract fields are missing';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(events) as item(value)
    where nullif(btrim(item.value ->> 'source_id'), '') is null
       or nullif(btrim(item.value ->> 'name'), '') is null
       or nullif(btrim(item.value ->> 'full_name'), '') is null
       or nullif(btrim(item.value ->> 'start_at'), '') is null
       or nullif(btrim(item.value ->> 'end_at'), '') is null
       or nullif(btrim(item.value ->> 'updated_at'), '') is null
       or (item.value -> 'source_state' <> 'null'::jsonb
           and jsonb_typeof(item.value -> 'source_state') <> 'number')
       or (item.value -> 'cover' <> 'null'::jsonb
           and coalesce(item.value ->> 'cover', '') !~ '^https?://')
       or (item.value -> 'source_url' <> 'null'::jsonb
           and coalesce(item.value ->> 'source_url', '') !~ '^https?://')
  ) then
    raise exception using
      errcode = '22023',
      message = 'INVALID_EVENT_RECORD',
      detail = 'A required value or URL has an invalid type or format';
  end if;

  if exists (
    select 1
    from jsonb_to_recordset(events) as item(name text, start_at text)
    group by item.name, item.start_at
    having count(*) > 1
  ) then
    raise exception using
      errcode = '23505',
      message = 'DUPLICATE_EVENT_KEY',
      detail = 'Duplicate (name, start_at) values are not allowed';
  end if;

  begin
    perform (item.value ->> 'start_at')::timestamptz,
            (item.value ->> 'end_at')::timestamptz,
            (item.value ->> 'updated_at')::timestamptz
    from jsonb_array_elements(events) as item(value);
  exception when others then
    raise exception using
      errcode = '22007',
      message = 'INVALID_EVENT_DATE',
      detail = 'One or more event timestamps are invalid';
  end;

  if exists (
    select 1
    from jsonb_to_recordset(events) as item(name text, start_at text)
    join public.furry_events existing
      on existing.name = item.name
     and existing.start_at = item.start_at
    where existing.source = 'legacy'
  ) then
    raise exception using
      errcode = '23505',
      message = 'LEGACY_EVENT_KEY_CONFLICT',
      detail = 'A legacy record already uses one of the incoming keys';
  end if;

  select count(*)
  into current_active
  from public.furry_events
  where source = source_name
    and is_active = true;

  if event_count = 0 and current_active > 0 and not allow_empty then
    raise exception using
      errcode = 'P0001',
      message = 'EMPTY_SNAPSHOT_REJECTED',
      detail = 'An empty snapshot cannot deactivate existing active events without allow_empty=true';
  end if;

  insert into public.furry_events (
    source_id,
    name,
    full_name,
    start_at,
    end_at,
    province,
    city,
    address,
    venue,
    cover,
    status,
    source_state,
    source_state_text,
    source_url,
    source_path,
    detail,
    organization,
    updated_at,
    source,
    is_active,
    last_seen_at
  )
  select
    item.source_id,
    item.name,
    item.full_name,
    item.start_at,
    item.end_at,
    item.province,
    item.city,
    item.address,
    item.venue,
    item.cover,
    item.status,
    item.source_state,
    item.source_state_text,
    item.source_url,
    item.source_path,
    item.detail,
    item.organization,
    item.updated_at,
    source_name,
    true,
    synced_at
  from jsonb_to_recordset(events) as item(
    source_id text,
    name text,
    full_name text,
    start_at text,
    end_at text,
    province text,
    city text,
    address text,
    venue text,
    cover text,
    status text,
    source_state integer,
    source_state_text text,
    source_url text,
    source_path text,
    detail text,
    organization text,
    updated_at text
  )
  on conflict (name, start_at) do update
  set source_id = excluded.source_id,
      full_name = excluded.full_name,
      end_at = excluded.end_at,
      province = excluded.province,
      city = excluded.city,
      address = excluded.address,
      venue = excluded.venue,
      cover = excluded.cover,
      status = excluded.status,
      source_state = excluded.source_state,
      source_state_text = excluded.source_state_text,
      source_url = excluded.source_url,
      source_path = excluded.source_path,
      detail = excluded.detail,
      organization = excluded.organization,
      updated_at = excluded.updated_at,
      source = source_name,
      is_active = true,
      last_seen_at = synced_at
  where public.furry_events.source = source_name;

  get diagnostics upsert_count = row_count;

  if upsert_count <> event_count then
    raise exception using
      errcode = 'P0001',
      message = 'SYNC_COUNT_MISMATCH',
      detail = format('Expected %s upserts but completed %s', event_count, upsert_count);
  end if;

  update public.furry_events existing
  set is_active = false
  where existing.source = source_name
    and existing.is_active = true
    and not exists (
      select 1
      from jsonb_to_recordset(events) as item(name text, start_at text)
      where item.name = existing.name
        and item.start_at = existing.start_at
    );

  get diagnostics deactivate_count = row_count;

  select count(*) filter (where is_active),
         count(*) filter (where not is_active)
  into active_count, inactive_count
  from public.furry_events
  where source = source_name;

  return query
  select upsert_count, deactivate_count, active_count, inactive_count;
end;
$$;

revoke all on function public.sync_furry_events(jsonb, timestamptz, boolean)
  from public, anon, authenticated;
grant execute on function public.sync_furry_events(jsonb, timestamptz, boolean)
  to service_role;
