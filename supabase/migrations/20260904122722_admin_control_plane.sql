-- Admin control plane. These objects are private to the API Worker; clients
-- never receive direct Data API grants for them.

create table if not exists public.pro_activations (
  id uuid primary key default gen_random_uuid(),
  user_id text not null references public.user_profiles(user_id),
  activated_at timestamptz not null default now(),
  source text not null check (source = 'payment'),
  order_id text null,
  created_at timestamptz not null default now()
);

create unique index if not exists pro_activations_order_id_unique
  on public.pro_activations(order_id)
  where order_id is not null;

create index if not exists pro_activations_user_activated_at_idx
  on public.pro_activations(user_id, activated_at desc);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null check (char_length(btrim(title)) between 1 and 120),
  content text not null check (char_length(btrim(content)) between 1 and 10000),
  is_active boolean not null default false,
  published_at timestamptz null,
  starts_at timestamptz null,
  ends_at timestamptz null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at > starts_at)
);

create index if not exists announcements_effective_idx
  on public.announcements(published_at desc)
  where is_active = true and published_at is not null;

create table if not exists public.admin_audit_logs (
  id uuid primary key default gen_random_uuid(),
  admin_user_id uuid not null,
  action text not null check (char_length(action) between 1 and 80),
  target_type text not null check (char_length(target_type) between 1 and 80),
  target_id text null check (target_id is null or char_length(target_id) <= 160),
  success boolean not null,
  result text not null check (char_length(result) between 1 and 120),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

create index if not exists admin_audit_logs_created_at_idx
  on public.admin_audit_logs(created_at desc);

alter table public.pro_activations enable row level security;
alter table public.announcements enable row level security;
alter table public.admin_audit_logs enable row level security;

revoke all on table public.pro_activations from public, anon, authenticated;
revoke all on table public.announcements from public, anon, authenticated;
revoke all on table public.admin_audit_logs from public, anon, authenticated;
grant all on table public.pro_activations to service_role;
grant all on table public.announcements to service_role;
grant all on table public.admin_audit_logs to service_role;

create or replace function public.sunland_activate_pro_from_payment(
  p_user_id text,
  p_order_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_existing_order_user_id text;
  v_is_pro boolean;
begin
  if char_length(btrim(coalesce(p_user_id, ''))) = 0
    or char_length(btrim(coalesce(p_order_id, ''))) = 0 then
    raise exception 'INVALID_PAYMENT_REFERENCE' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('payment-order:' || p_order_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('payment-user:' || p_user_id, 0)
  );

  select pa.user_id
    into v_existing_order_user_id
    from public.pro_activations pa
   where pa.order_id = p_order_id;

  if found then
    if v_existing_order_user_id <> p_user_id then
      raise exception 'PAYMENT_ORDER_USER_MISMATCH' using errcode = '22023';
    end if;
    return jsonb_build_object('status', 'already_processed');
  end if;

  select up.pro
    into v_is_pro
    from public.user_profiles up
   where up.user_id = p_user_id
   for update;

  if not found then
    insert into public.user_profiles (user_id, pro)
    values (p_user_id, true);
  elsif coalesce(v_is_pro, false) then
    return jsonb_build_object('status', 'already_pro');
  else
    update public.user_profiles
       set pro = true
     where user_id = p_user_id;
  end if;

  insert into public.pro_activations (user_id, source, order_id)
  values (p_user_id, 'payment', p_order_id);

  return jsonb_build_object('status', 'activated');
end;
$$;

create or replace function public.sunland_admin_record_failed_action(
  p_admin_user_id uuid,
  p_action text,
  p_target_type text,
  p_target_id text,
  p_result text,
  p_metadata jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if jsonb_typeof(coalesce(p_metadata, '{}'::jsonb)) <> 'object' then
    raise exception 'INVALID_AUDIT_METADATA' using errcode = '22023';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result, metadata
  ) values (
    p_admin_user_id,
    p_action,
    p_target_type,
    p_target_id,
    false,
    p_result,
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

create or replace function public.sunland_admin_set_maintenance(
  p_admin_user_id uuid,
  p_enabled boolean,
  p_title text,
  p_message text,
  p_estimated_end timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_config jsonb;
begin
  update public.app_config
     set maintenance_enabled = p_enabled,
         maintenance_title = btrim(p_title),
         maintenance_message = btrim(p_message),
         maintenance_estimated_end = p_estimated_end,
         updated_at = now()
   where id = 'global'
   returning jsonb_build_object(
     'enabled', maintenance_enabled,
     'title', maintenance_title,
     'message', maintenance_message,
     'estimatedEnd', maintenance_estimated_end,
     'updatedAt', updated_at
   ) into v_config;

  if v_config is null then
    raise exception 'MAINTENANCE_CONFIG_NOT_FOUND' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result, metadata
  ) values (
    p_admin_user_id,
    case when p_enabled then 'maintenance_enabled' else 'maintenance_disabled' end,
    'app_config',
    'global',
    true,
    'SUCCESS',
    jsonb_build_object('enabled', p_enabled, 'estimatedEnd', p_estimated_end)
  );

  return v_config;
end;
$$;

create or replace function public.sunland_admin_create_announcement(
  p_admin_user_id uuid,
  p_title text,
  p_content text,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid;
begin
  insert into public.announcements (title, content, starts_at, ends_at)
  values (btrim(p_title), btrim(p_content), p_starts_at, p_ends_at)
  returning id into v_id;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result
  ) values (
    p_admin_user_id, 'announcement_created', 'announcement', v_id::text, true, 'SUCCESS'
  );

  return (select to_jsonb(a) from public.announcements a where a.id = v_id);
end;
$$;

create or replace function public.sunland_admin_update_announcement(
  p_admin_user_id uuid,
  p_id uuid,
  p_title text,
  p_content text,
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_is_active boolean;
begin
  select a.is_active into v_is_active
    from public.announcements a
   where a.id = p_id
   for update;
  if not found then
    raise exception 'ANNOUNCEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_is_active then
    raise exception 'ANNOUNCEMENT_ACTIVE' using errcode = 'P0001';
  end if;

  update public.announcements
     set title = btrim(p_title),
         content = btrim(p_content),
         starts_at = p_starts_at,
         ends_at = p_ends_at,
         updated_at = now()
   where id = p_id;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result
  ) values (
    p_admin_user_id, 'announcement_updated', 'announcement', p_id::text, true, 'SUCCESS'
  );

  return (select to_jsonb(a) from public.announcements a where a.id = p_id);
end;
$$;

create or replace function public.sunland_admin_set_announcement_active(
  p_admin_user_id uuid,
  p_id uuid,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.announcements
     set is_active = p_active,
         published_at = case
           when p_active then coalesce(published_at, now())
           else published_at
         end,
         updated_at = now()
   where id = p_id;

  if not found then
    raise exception 'ANNOUNCEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result,
    metadata
  ) values (
    p_admin_user_id,
    case when p_active then 'announcement_published' else 'announcement_unpublished' end,
    'announcement',
    p_id::text,
    true,
    'SUCCESS',
    jsonb_build_object('active', p_active)
  );

  return (select to_jsonb(a) from public.announcements a where a.id = p_id);
end;
$$;

create or replace function public.sunland_admin_delete_draft_announcement(
  p_admin_user_id uuid,
  p_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_published_at timestamptz;
begin
  select a.published_at into v_published_at
    from public.announcements a
   where a.id = p_id
   for update;
  if not found then
    raise exception 'ANNOUNCEMENT_NOT_FOUND' using errcode = 'P0001';
  end if;
  if v_published_at is not null then
    raise exception 'ANNOUNCEMENT_WAS_PUBLISHED' using errcode = 'P0001';
  end if;

  delete from public.announcements where id = p_id;
  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result
  ) values (
    p_admin_user_id, 'announcement_deleted', 'announcement', p_id::text, true, 'SUCCESS'
  );
end;
$$;

create or replace function public.sunland_admin_stats()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with bounds as (
    select (date_trunc('day', now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai') as today_start
  ), series as (
    select generate_series(
      (select today_start from bounds) - interval '29 days',
      (select today_start from bounds),
      interval '1 day'
    ) as day_start
  )
  select jsonb_build_object(
    'users', jsonb_build_object(
      'total', (select count(*) from public.user_profiles),
      'today', (select count(*) from public.user_profiles, bounds where created_at >= today_start),
      'last7Days', (select count(*) from public.user_profiles, bounds where created_at >= today_start - interval '6 days'),
      'last30Days', (select count(*) from public.user_profiles, bounds where created_at >= today_start - interval '29 days'),
      'trend', (
        select coalesce(
          jsonb_agg(jsonb_build_object('date', daily.day_start::date, 'count', daily.user_count) order by daily.day_start),
          '[]'::jsonb
        )
        from (
          select s.day_start, count(up.user_id) as user_count
          from series s
          left join public.user_profiles up
            on up.created_at >= s.day_start and up.created_at < s.day_start + interval '1 day'
          group by s.day_start
        ) daily
      )
    ),
    'pro', jsonb_build_object(
      'total', (select count(*) from public.user_profiles where pro = true),
      'standard', (select count(*) from public.user_profiles where pro is distinct from true),
      'today', (select count(*) from public.pro_activations, bounds where activated_at >= today_start),
      'last7Days', (select count(*) from public.pro_activations, bounds where activated_at >= today_start - interval '6 days'),
      'last30Days', (select count(*) from public.pro_activations, bounds where activated_at >= today_start - interval '29 days')
    ),
    'usageAvailable', false
  );
$$;

create or replace function public.sunland_admin_list_users(
  p_query text,
  p_page integer,
  p_page_size integer,
  p_sort text default 'created_at',
  p_desc boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_page integer := greatest(1, coalesce(p_page, 1));
  v_page_size integer := least(100, greatest(1, coalesce(p_page_size, 20)));
  v_sort text := lower(coalesce(p_sort, 'created_at'));
  v_query text := nullif(btrim(p_query), '');
  v_result jsonb;
begin
  if v_sort not in ('created_at', 'name', 'email', 'pro') then
    v_sort := 'created_at';
  end if;

  with filtered as materialized (
    select up.user_id, up.name, up.email, up.avatar_url, up.pro, up.is_banned, up.created_at
      from public.user_profiles up
     where v_query is null
        or up.user_id ilike '%' || v_query || '%'
        or coalesce(up.email, '') ilike '%' || v_query || '%'
        or coalesce(up.name, '') ilike '%' || v_query || '%'
  ), ordered as materialized (
    select filtered.*, row_number() over (
      order by
        case when v_sort = 'created_at' and not p_desc then created_at end asc nulls last,
        case when v_sort = 'created_at' and p_desc then created_at end desc nulls last,
        case when v_sort = 'name' and not p_desc then lower(coalesce(name, '')) end asc,
        case when v_sort = 'name' and p_desc then lower(coalesce(name, '')) end desc,
        case when v_sort = 'email' and not p_desc then lower(coalesce(email, '')) end asc,
        case when v_sort = 'email' and p_desc then lower(coalesce(email, '')) end desc,
        case when v_sort = 'pro' and not p_desc then pro end asc,
        case when v_sort = 'pro' and p_desc then pro end desc,
        user_id asc
    ) as list_order
    from filtered
  ), page_rows as materialized (
    select * from ordered
     where list_order > (v_page - 1) * v_page_size
       and list_order <= v_page * v_page_size
  ), conversation_aggregate as materialized (
    select c.user_id,
      coalesce(sum(jsonb_array_length(c.data)), 0)::integer as conversation_count,
      max(activity.last_active_at) as last_active_at
    from public.conversations c
    join page_rows pr on pr.user_id = c.user_id
    left join lateral (
      select max(
        case when coalesce(conversation ->> 'updatedAt', '') ~ '^[0-9]+$'
          then to_timestamp((conversation ->> 'updatedAt')::numeric / 1000.0)
        end
      ) as last_active_at
      from jsonb_array_elements(coalesce(c.data, '[]'::jsonb)) conversation
    ) activity on true
    group by c.user_id
  ), page_with_conversations as (
    select pr.*, coalesce(ca.conversation_count, 0) as conversation_count,
      ca.last_active_at
    from page_rows pr
    left join conversation_aggregate ca on ca.user_id = pr.user_id
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'userId', user_id,
      'name', name,
      'email', email,
      'avatarUrl', avatar_url,
      'isPro', pro = true,
      'isBanned', is_banned = true,
      'createdAt', created_at,
      'conversationCount', conversation_count,
      'lastActiveAt', last_active_at
    ) order by list_order), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'page', v_page,
    'pageSize', v_page_size
  ) into v_result
  from page_with_conversations;

  return v_result;
end;
$$;

create or replace function public.sunland_admin_user_detail(p_user_id text)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'userId', up.user_id,
    'name', up.name,
    'email', up.email,
    'avatarUrl', up.avatar_url,
    'isPro', up.pro = true,
    'isBanned', up.is_banned = true,
    'createdAt', up.created_at,
    'conversationCount', coalesce(jsonb_array_length(c.data), 0),
    'userMessageCount', detail.user_message_count,
    'assistantMessageCount', detail.assistant_message_count,
    'lastActiveAt', detail.last_active_at,
    'recentModel', detail.latest_model,
    'proActivatedAt', activation.activated_at,
    'proSource', activation.source,
    'orderId', activation.order_id
  )
  from public.user_profiles up
  left join public.conversations c on c.user_id = up.user_id
  left join lateral (
    select
      count(message) filter (where message ->> 'role' = 'user') as user_message_count,
      count(message) filter (where message ->> 'role' = 'assistant') as assistant_message_count,
      max(case when coalesce(conversation ->> 'updatedAt', '') ~ '^[0-9]+$'
        then to_timestamp((conversation ->> 'updatedAt')::numeric / 1000.0) end) as last_active_at,
      (array_agg(nullif(conversation ->> 'model', '') order by (conversation ->> 'updatedAt') desc nulls last))[1] as latest_model
    from jsonb_array_elements(coalesce(c.data, '[]'::jsonb)) conversation
    left join lateral jsonb_array_elements(
      case when jsonb_typeof(conversation -> 'history') = 'array' then conversation -> 'history' else '[]'::jsonb end
    ) message on true
  ) detail on true
  left join lateral (
    select pa.activated_at, pa.source, pa.order_id
      from public.pro_activations pa
     where pa.user_id = up.user_id
     order by pa.activated_at desc
     limit 1
  ) activation on true
  where up.user_id = p_user_id;
$$;

create or replace function public.sunland_admin_pro_stats()
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with bounds as (
    select (date_trunc('day', now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai') as today_start
  )
  select jsonb_build_object(
    'total', (select count(*) from public.user_profiles where pro = true),
    'ratio', case when (select count(*) from public.user_profiles) = 0 then 0
                  else round((select count(*) from public.user_profiles where pro = true)::numeric / (select count(*) from public.user_profiles), 4) end,
    'today', (select count(*) from public.pro_activations, bounds where activated_at >= today_start),
    'last7Days', (select count(*) from public.pro_activations, bounds where activated_at >= today_start - interval '6 days'),
    'last30Days', (select count(*) from public.pro_activations, bounds where activated_at >= today_start - interval '29 days')
  );
$$;

create or replace function public.sunland_admin_list_pro_activations(
  p_query text,
  p_page integer,
  p_page_size integer
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with args as (
    select nullif(btrim(p_query), '') as query,
      greatest(1, coalesce(p_page, 1)) as page,
      least(100, greatest(1, coalesce(p_page_size, 20))) as page_size
  ), filtered as materialized (
    select pa.id, pa.user_id, pa.activated_at, pa.source, pa.order_id, up.name, up.email
      from public.pro_activations pa
      join public.user_profiles up on up.user_id = pa.user_id
      cross join args
     where args.query is null
        or pa.user_id ilike '%' || args.query || '%'
        or coalesce(up.email, '') ilike '%' || args.query || '%'
        or coalesce(up.name, '') ilike '%' || args.query || '%'
  ), page_rows as (
    select filtered.*
      from filtered cross join args
     order by activated_at desc
     limit (select page_size from args)
    offset ((select page from args) - 1) * (select page_size from args)
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'userId', user_id, 'name', name, 'email', email,
      'activatedAt', activated_at, 'source', source, 'orderId', order_id
    ) order by activated_at desc), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'page', (select page from args),
    'pageSize', (select page_size from args)
  )
  from page_rows;
$$;

create or replace function public.sunland_public_announcements(
  p_page integer,
  p_page_size integer
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  with args as (
    select greatest(1, coalesce(p_page, 1)) as page,
      least(100, greatest(1, coalesce(p_page_size, 20))) as page_size
  ), effective as materialized (
    select a.id, a.title, a.content, a.published_at, a.starts_at, a.ends_at
      from public.announcements a
     where a.published_at is not null
       and a.is_active = true
       and (a.starts_at is null or a.starts_at <= now())
       and (a.ends_at is null or a.ends_at > now())
  ), page_rows as (
    select effective.*
      from effective cross join args
     order by published_at desc, id desc
     limit (select page_size from args)
    offset ((select page from args) - 1) * (select page_size from args)
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'title', title, 'content', content,
      'publishedAt', published_at, 'startsAt', starts_at, 'endsAt', ends_at
    ) order by published_at desc, id desc), '[]'::jsonb),
    'total', (select count(*) from effective),
    'page', (select page from args),
    'pageSize', (select page_size from args)
  )
  from page_rows;
$$;

revoke execute on function public.sunland_activate_pro_from_payment(text, text) from public, anon, authenticated;
revoke execute on function public.sunland_admin_record_failed_action(uuid, text, text, text, text, jsonb) from public, anon, authenticated;
revoke execute on function public.sunland_admin_set_maintenance(uuid, boolean, text, text, timestamptz) from public, anon, authenticated;
revoke execute on function public.sunland_admin_create_announcement(uuid, text, text, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.sunland_admin_update_announcement(uuid, uuid, text, text, timestamptz, timestamptz) from public, anon, authenticated;
revoke execute on function public.sunland_admin_set_announcement_active(uuid, uuid, boolean) from public, anon, authenticated;
revoke execute on function public.sunland_admin_delete_draft_announcement(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.sunland_admin_stats() from public, anon, authenticated;
revoke execute on function public.sunland_admin_list_users(text, integer, integer, text, boolean) from public, anon, authenticated;
revoke execute on function public.sunland_admin_user_detail(text) from public, anon, authenticated;
revoke execute on function public.sunland_admin_pro_stats() from public, anon, authenticated;
revoke execute on function public.sunland_admin_list_pro_activations(text, integer, integer) from public, anon, authenticated;
revoke execute on function public.sunland_public_announcements(integer, integer) from public, anon, authenticated;

grant execute on function public.sunland_activate_pro_from_payment(text, text) to service_role;
grant execute on function public.sunland_admin_record_failed_action(uuid, text, text, text, text, jsonb) to service_role;
grant execute on function public.sunland_admin_set_maintenance(uuid, boolean, text, text, timestamptz) to service_role;
grant execute on function public.sunland_admin_create_announcement(uuid, text, text, timestamptz, timestamptz) to service_role;
grant execute on function public.sunland_admin_update_announcement(uuid, uuid, text, text, timestamptz, timestamptz) to service_role;
grant execute on function public.sunland_admin_set_announcement_active(uuid, uuid, boolean) to service_role;
grant execute on function public.sunland_admin_delete_draft_announcement(uuid, uuid) to service_role;
grant execute on function public.sunland_admin_stats() to service_role;
grant execute on function public.sunland_admin_list_users(text, integer, integer, text, boolean) to service_role;
grant execute on function public.sunland_admin_user_detail(text) to service_role;
grant execute on function public.sunland_admin_pro_stats() to service_role;
grant execute on function public.sunland_admin_list_pro_activations(text, integer, integer) to service_role;
grant execute on function public.sunland_public_announcements(integer, integer) to service_role;

-- The legacy code claim function remains for historical inspection only. No
-- Data API role, including service_role, may invoke it after retirement.
revoke execute on function public.sunland_claim_activation_code(text, text)
  from public, anon, authenticated, service_role;
