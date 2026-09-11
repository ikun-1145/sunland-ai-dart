-- The payment pipeline now records successful orders in pro_payment_orders.
-- Keep the existing Admin response envelope while reading that authoritative
-- activation ledger instead of the retired pro_activations table.

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
    'today', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start),
    'last7Days', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start - interval '6 days'),
    'last30Days', (select count(*) from public.pro_payment_orders, bounds where status = 'activated' and activated_at >= today_start - interval '29 days')
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
    select po.order_id as id,
      po.bound_user_id as user_id,
      po.activated_at,
      po.binding_source,
      po.order_id,
      up.name,
      up.email
      from public.pro_payment_orders po
      left join public.user_profiles up on up.user_id = po.bound_user_id
      cross join args
     where po.status = 'activated'
       and po.bound_user_id is not null
       and (args.query is null
         or po.order_id ilike '%' || args.query || '%'
         or po.bound_user_id ilike '%' || args.query || '%'
         or coalesce(up.email, '') ilike '%' || args.query || '%'
         or coalesce(up.name, '') ilike '%' || args.query || '%')
  ), page_rows as (
    select filtered.*
      from filtered cross join args
     order by activated_at desc, id desc
     limit (select page_size from args)
    offset ((select page from args) - 1) * (select page_size from args)
  )
  select jsonb_build_object(
    'items', coalesce(jsonb_agg(jsonb_build_object(
      'id', id,
      'userId', user_id,
      'name', name,
      'email', email,
      'activatedAt', activated_at,
      'source', 'payment',
      'bindingSource', binding_source,
      'orderId', order_id
    ) order by activated_at desc, id desc), '[]'::jsonb),
    'total', (select count(*) from filtered),
    'page', (select page from args),
    'pageSize', (select page_size from args)
  )
  from page_rows;
$$;
