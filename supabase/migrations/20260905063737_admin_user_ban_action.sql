-- Admin-only user ban mutation. The Worker has already authenticated the
-- unique administrator before invoking this function with service_role.
create or replace function public.sunland_admin_set_user_ban(
  p_admin_user_id uuid,
  p_user_id text,
  p_is_banned boolean
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if char_length(btrim(coalesce(p_user_id, ''))) = 0 then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  update public.user_profiles
     set is_banned = p_is_banned,
         ban_reason = case
           when p_is_banned then '账户已被管理员封禁'
           else null
         end,
         updated_at = now()
   where user_id = p_user_id
   returning jsonb_build_object(
     'userId', user_id,
     'isBanned', is_banned,
     'banReason', ban_reason
   ) into v_result;

  if v_result is null then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result, metadata
  ) values (
    p_admin_user_id,
    case when p_is_banned then 'user_banned' else 'user_unbanned' end,
    'user_profile',
    p_user_id,
    true,
    'SUCCESS',
    jsonb_build_object('banned', p_is_banned)
  );

  return v_result;
end;
$$;

revoke execute on function public.sunland_admin_set_user_ban(uuid, text, boolean)
  from public, anon, authenticated;
grant execute on function public.sunland_admin_set_user_ban(uuid, text, boolean)
  to service_role;
