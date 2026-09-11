begin;

alter table public.user_profiles
  add column if not exists identity_status text not null default 'active',
  add column if not exists deletion_job_id uuid,
  add column if not exists deletion_attempt_id text,
  add column if not exists deletion_fencing_version bigint not null default 0,
  add column if not exists deletion_started_at timestamptz,
  add column if not exists retired_at timestamptz;

alter table public.user_profiles
  drop constraint if exists user_profiles_identity_status_check;
alter table public.user_profiles
  add constraint user_profiles_identity_status_check
  check (identity_status in ('active', 'deleting', 'retired'));

drop index if exists public.user_profiles_email_unique_idx;
create unique index user_profiles_email_unique_idx
  on public.user_profiles (lower(email))
  where email is not null
    and identity_status is distinct from 'retired';

create or replace function public.sunland_account_delete_begin(
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

  select identity_status, deletion_job_id, deletion_attempt_id, deletion_fencing_version
    into v_status, v_job, v_attempt, v_version
  from public.user_profiles
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'code', 'user_not_found',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id
    );
  end if;

  if v_status = 'retired' then
    return jsonb_build_object(
      'code', 'retired',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_status = 'deleting' then
    if v_job is distinct from p_deletion_job_id then
      return jsonb_build_object(
        'code', 'deletion_conflict',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    if p_fencing_version < v_version then
      return jsonb_build_object(
        'code', 'stale_attempt',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    if p_fencing_version = v_version then
      if p_attempt_id is distinct from v_attempt then
        return jsonb_build_object(
          'code', 'fencing_conflict',
          'deletion_job_id', p_deletion_job_id::text,
          'user_id', p_user_id,
          'attempt_id', v_attempt,
          'fencing_version', v_version
        );
      end if;

      return jsonb_build_object(
        'code', 'already_revoked',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    update public.user_profiles
       set deletion_attempt_id = p_attempt_id,
           deletion_fencing_version = p_fencing_version,
           deletion_started_at = now()
     where user_id = p_user_id;

    return jsonb_build_object(
      'code', 'ownership_transferred',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', p_attempt_id,
      'fencing_version', p_fencing_version
    );
  end if;

  if v_status = 'active' then
    update public.user_profiles
       set identity_status = 'deleting',
           deletion_job_id = p_deletion_job_id,
           deletion_attempt_id = p_attempt_id,
           deletion_fencing_version = p_fencing_version,
           deletion_started_at = now()
     where user_id = p_user_id;

    return jsonb_build_object(
      'code', 'revoked',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', p_attempt_id,
      'fencing_version', p_fencing_version
    );
  end if;

  return jsonb_build_object(
    'code', 'invalid_state',
    'deletion_job_id', p_deletion_job_id::text,
    'user_id', p_user_id,
    'attempt_id', v_attempt,
    'fencing_version', v_version
  );
end;
$$;

revoke all on function public.sunland_account_delete_begin(text, uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.sunland_account_delete_begin(text, uuid, text, bigint)
  to service_role;

create or replace function public.sunland_account_delete_finalize(
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

  select identity_status, deletion_job_id, deletion_attempt_id, deletion_fencing_version
    into v_status, v_job, v_attempt, v_version
  from public.user_profiles
  where user_id = p_user_id
  for update;

  if not found then
    return jsonb_build_object(
      'code', 'user_not_found',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_status = 'retired' then
    if v_job = p_deletion_job_id
      and v_attempt = p_attempt_id
      and v_version = p_fencing_version then
      return jsonb_build_object(
        'code', 'already_retired',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    return jsonb_build_object(
      'code', 'stale_attempt',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_status = 'active' then
    return jsonb_build_object(
      'code', 'not_deleting',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  if v_status = 'deleting' then
    if v_job is distinct from p_deletion_job_id then
      return jsonb_build_object(
        'code', 'deletion_conflict',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    if p_fencing_version is distinct from v_version then
      return jsonb_build_object(
        'code', 'stale_attempt',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    if p_attempt_id is distinct from v_attempt then
      return jsonb_build_object(
        'code', 'fencing_conflict',
        'deletion_job_id', p_deletion_job_id::text,
        'user_id', p_user_id,
        'attempt_id', v_attempt,
        'fencing_version', v_version
      );
    end if;

    update public.user_profiles
       set identity_status = 'retired',
           retired_at = now()
     where user_id = p_user_id;

    return jsonb_build_object(
      'code', 'retired',
      'deletion_job_id', p_deletion_job_id::text,
      'user_id', p_user_id,
      'attempt_id', v_attempt,
      'fencing_version', v_version
    );
  end if;

  return jsonb_build_object(
    'code', 'invalid_state',
    'deletion_job_id', p_deletion_job_id::text,
    'user_id', p_user_id,
    'attempt_id', v_attempt,
    'fencing_version', v_version
  );
end;
$$;

revoke all on function public.sunland_account_delete_finalize(text, uuid, text, bigint)
  from public, anon, authenticated;
grant execute on function public.sunland_account_delete_finalize(text, uuid, text, bigint)
  to service_role;

commit;
