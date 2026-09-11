-- Keep dashboard and user detail Pro fields on the same payment-order ledger
-- used by the Admin activation list.

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
      'today', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start),
      'last7Days', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start - interval '6 days'),
      'last30Days', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start - interval '29 days')
    ),
    'usageAvailable', false
  );
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
    'banReason', up.ban_reason,
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
    select po.activated_at, 'payment'::text as source, po.order_id
      from public.pro_payment_orders po
     where po.bound_user_id = up.user_id
       and po.status = 'activated'
     order by po.activated_at desc
     limit 1
  ) activation on true
  where up.user_id = p_user_id;
$$;
