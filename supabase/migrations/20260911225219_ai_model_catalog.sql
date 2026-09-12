-- Public display catalogue only; AI routing and server-side entitlements stay unchanged.
create table public.ai_models (
  id uuid primary key default gen_random_uuid(),
  provider text not null check (provider in ('deepseek', 'sunland')),
  display_name text not null check (
    char_length(btrim(display_name)) between 1 and 80
    and display_name !~ '[[:cntrl:]]'
  ),
  model_name text not null check (char_length(model_name) between 1 and 120),
  free_enabled boolean not null default false,
  pro_enabled boolean not null default false,
  enabled boolean not null default true,
  sort_order integer not null default 0 check (sort_order between 0 and 10000),
  updated_at timestamptz not null default clock_timestamp(),
  unique (provider, model_name),
  constraint ai_models_supported_route check (
    (provider = 'deepseek' and model_name in ('deepseek-v4-flash', 'deepseek-v4-pro'))
    or (provider = 'sunland' and model_name = 'frost')
  ),
  constraint ai_models_pro_entitlement check (model_name <> 'deepseek-v4-pro' or not free_enabled)
);

alter table public.ai_models enable row level security;
revoke all on table public.ai_models from public, anon, authenticated;
grant select on table public.ai_models to anon, authenticated;
grant all on table public.ai_models to service_role;
create policy ai_models_public_read on public.ai_models
  for select to anon, authenticated using (enabled);

insert into public.ai_models (provider, display_name, model_name, free_enabled, pro_enabled, sort_order)
values
  ('deepseek', 'DeepSeek V4 Flash', 'deepseek-v4-flash', true, true, 10),
  ('deepseek', 'DeepSeek V4 Pro', 'deepseek-v4-pro', false, true, 20),
  ('sunland', 'Sunland AI · Beta', 'frost', true, true, 30);

create function public.sunland_admin_list_ai_models()
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object('items', coalesce(jsonb_agg(to_jsonb(m) order by m.sort_order, m.id), '[]'::jsonb))
    from public.ai_models m;
$$;

create function public.sunland_admin_save_ai_model(
  p_admin_user_id uuid,
  p_id uuid,
  p_provider text,
  p_display_name text,
  p_model_name text,
  p_free_enabled boolean,
  p_pro_enabled boolean,
  p_enabled boolean,
  p_sort_order integer,
  p_updated_at timestamptz
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row public.ai_models;
begin
  if p_admin_user_id is null or (p_id is null and p_updated_at is not null) then
    raise exception 'AI_MODEL_INVALID_INPUT' using errcode = '22023';
  end if;

  -- Serialize this tiny admin catalogue so concurrent saves cannot empty a plan.
  perform pg_catalog.pg_advisory_xact_lock(20260911, 1);

  if p_id is null then
    insert into public.ai_models (
      provider, display_name, model_name, free_enabled, pro_enabled, enabled, sort_order
    ) values (
      p_provider, btrim(p_display_name), p_model_name, p_free_enabled, p_pro_enabled, p_enabled, p_sort_order
    ) returning * into v_row;
  else
    select * into v_row from public.ai_models where id = p_id for update;
    if not found then
      raise exception 'AI_MODEL_NOT_FOUND' using errcode = 'P0001';
    end if;
    if p_updated_at is null or v_row.updated_at <> p_updated_at then
      raise exception 'AI_MODEL_CONFLICT' using errcode = 'P0001';
    end if;
    update public.ai_models
       set provider = p_provider,
           display_name = btrim(p_display_name),
           model_name = p_model_name,
           free_enabled = p_free_enabled,
           pro_enabled = p_pro_enabled,
           enabled = p_enabled,
           sort_order = p_sort_order,
           updated_at = greatest(clock_timestamp(), v_row.updated_at + interval '1 microsecond')
     where id = p_id
     returning * into v_row;
  end if;

  if not exists (select 1 from public.ai_models where provider = 'deepseek' and enabled and free_enabled)
     or not exists (select 1 from public.ai_models where provider = 'deepseek' and enabled and pro_enabled) then
    raise exception 'AI_MODEL_REQUIRED' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result, metadata
  ) values (
    p_admin_user_id, 'ai_model_saved', 'ai_model', v_row.id::text, true, 'SUCCESS',
    jsonb_build_object('provider', v_row.provider, 'model_name', v_row.model_name,
      'free_enabled', v_row.free_enabled, 'pro_enabled', v_row.pro_enabled, 'enabled', v_row.enabled)
  );
  return to_jsonb(v_row);
end;
$$;

revoke execute on function public.sunland_admin_list_ai_models() from public, anon, authenticated;
revoke execute on function public.sunland_admin_save_ai_model(uuid, uuid, text, text, text, boolean, boolean, boolean, integer, timestamptz) from public, anon, authenticated;
grant execute on function public.sunland_admin_list_ai_models() to service_role;
grant execute on function public.sunland_admin_save_ai_model(uuid, uuid, text, text, text, boolean, boolean, boolean, integer, timestamptz) to service_role;
