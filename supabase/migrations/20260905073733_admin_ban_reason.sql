-- Preserve an operator-supplied reason for Admin bans. The Worker authenticates
-- the unique administrator before invoking this service-role-only function.
create or replace function public.sunland_admin_set_user_ban_with_reason(
  p_admin_user_id uuid,
  p_user_id text,
  p_is_banned boolean,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_reason text := nullif(btrim(coalesce(p_reason, '')), '');
  v_result jsonb;
begin
  if char_length(btrim(coalesce(p_user_id, ''))) = 0 then
    raise exception 'USER_NOT_FOUND' using errcode = 'P0001';
  end if;

  if p_is_banned and (v_reason is null or char_length(v_reason) > 500) then
    raise exception 'BAN_REASON_INVALID' using errcode = 'P0001';
  end if;

  update public.user_profiles
     set is_banned = p_is_banned,
         ban_reason = case when p_is_banned then v_reason else null end,
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
    select pa.activated_at, pa.source, pa.order_id
      from public.pro_activations pa
     where pa.user_id = up.user_id
     order by pa.activated_at desc
     limit 1
  ) activation on true
  where up.user_id = p_user_id;
$$;

revoke execute on function public.sunland_admin_set_user_ban_with_reason(uuid, text, boolean, text)
  from public, anon, authenticated;
grant execute on function public.sunland_admin_set_user_ban_with_reason(uuid, text, boolean, text)
  to service_role;

revoke execute on function public.sunland_admin_user_detail(text)
  from public, anon, authenticated;
grant execute on function public.sunland_admin_user_detail(text)
  to service_role;
