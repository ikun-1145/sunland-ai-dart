begin;

alter table public.user_profiles
  add column if not exists profile_sanitized_at timestamptz;

create or replace function public.sunland_account_delete_sanitize_profile(
  p_user_id text,
  p_deletion_job_id uuid,
  p_attempt_id text,
  p_fencing_version bigint
)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, extensions
as $$
declare
  v_status text;
  v_job uuid;
  v_attempt text;
  v_version bigint;
  v_sanitized_at timestamptz;
begin
  if p_user_id is null
    or p_user_id !~ '^[A-Za-z0-9][A-Za-z0-9@._+-]{0,127}$'
    or p_deletion_job_id is null
    or p_attempt_id is null
    or p_attempt_id !~ '^[A-Za-z0-9_-]{16,128}$'
    or p_fencing_version is null
    or p_fencing_version < 1 then
    return jsonb_build_object('code', 'invalid_request');
  end if;

  select identity_status, deletion_job_id, deletion_attempt_id, deletion_fencing_version, profile_sanitized_at
    into v_status, v_job, v_attempt, v_version, v_sanitized_at
  from public.user_profiles
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'code', 'user_not_found',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', p_attempt_id,
      'fencing_version', p_fencing_version
    );
  end if;

  if v_status is distinct from 'retired' then
    return jsonb_build_object(
      'code', 'not_retired',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_job is distinct from p_deletion_job_id
    or v_version is distinct from p_fencing_version then
    return jsonb_build_object(
      'code', 'stale_attempt',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_attempt is distinct from p_attempt_id then
    return jsonb_build_object(
      'code', 'fencing_conflict',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_sanitized_at is not null then
    return jsonb_build_object(
      'code', 'already_sanitized',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  update public.user_profiles
     set email = null,
         avatar_url = null,
         avatar_path = null,
         name = null,
         pro = false,
         is_banned = false,
         ban_reason = null,
         updated_at = now(),
         profile_sanitized_at = now()
   where user_id = p_user_id;

  return jsonb_build_object(
    'code', 'sanitized',
    'deletion_job_id', p_deletion_job_id::text,
    'user_id', p_user_id,
    'attempt_id', p_attempt_id,
    'fencing_version', p_fencing_version
  );
end;
$$;

revoke all on function public.sunland_account_delete_sanitize_profile(text, uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.sunland_account_delete_sanitize_profile(text, uuid, text, bigint)
  to service_role;

commit;
