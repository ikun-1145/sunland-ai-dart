-- Admin-only profile reset actions are transactional with their success audit
-- records. The Worker alone holds the service-role credential that can call
-- these functions.

create or replace function public.sunland_admin_reset_user_nickname(
  p_admin_user_id uuid,
  p_user_id text
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
     set name = '',
         updated_at = now()
   where user_id = p_user_id
   returning jsonb_build_object('userId', user_id, 'name', name) into v_result;

  if v_result is null then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result
  ) values (
    p_admin_user_id, 'user_nickname_reset', 'user_profile', p_user_id, true, 'SUCCESS'
  );

  return v_result;
end;
$$;

create or replace function public.sunland_admin_reset_user_avatar(
  p_admin_user_id uuid,
  p_user_id text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_previous_avatar_path text;
  v_result jsonb;
begin
  if char_length(btrim(coalesce(p_user_id, ''))) = 0 then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  select up.avatar_path
    into v_previous_avatar_path
    from public.user_profiles up
   where up.user_id = p_user_id
   for update;

  if not found then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  update public.user_profiles
     set avatar_url = '',
         avatar_path = '',
         updated_at = now()
   where user_id = p_user_id
   returning jsonb_build_object(
     'userId', user_id,
     'avatarUrl', avatar_url,
     'previousAvatarPath', v_previous_avatar_path
   ) into v_result;

  insert into public.admin_audit_logs (
    admin_user_id, action, target_type, target_id, success, result
  ) values (
    p_admin_user_id, 'user_avatar_reset', 'user_profile', p_user_id, true, 'SUCCESS'
  );

  return v_result;
end;
$$;

create or replace function public.sunland_admin_record_system_status_check(
  p_admin_user_id uuid,
  p_metadata jsonb
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
    'system_status_checked',
    'system',
    'api',
    true,
    'SUCCESS',
    coalesce(p_metadata, '{}'::jsonb)
  );
end;
$$;

revoke execute on function public.sunland_admin_reset_user_nickname(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.sunland_admin_reset_user_avatar(uuid, text)
  from public, anon, authenticated;
revoke execute on function public.sunland_admin_record_system_status_check(uuid, jsonb)
  from public, anon, authenticated;

grant execute on function public.sunland_admin_reset_user_nickname(uuid, text)
  to service_role;
grant execute on function public.sunland_admin_reset_user_avatar(uuid, text)
  to service_role;
grant execute on function public.sunland_admin_record_system_status_check(uuid, jsonb)
  to service_role;
