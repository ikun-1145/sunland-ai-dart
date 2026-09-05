-- The existing app_config table is keyed by config_key, not id. Keep the
-- maintenance change and its success audit in the same transaction.
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
   where config_key = 'global'
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

revoke execute on function public.sunland_admin_set_maintenance(uuid, boolean, text, text, timestamptz)
  from public, anon, authenticated;
grant execute on function public.sunland_admin_set_maintenance(uuid, boolean, text, text, timestamptz)
  to service_role;
