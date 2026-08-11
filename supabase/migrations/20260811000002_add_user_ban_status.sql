alter table public.user_profiles
  add column if not exists is_banned boolean not null default false,
  add column if not exists ban_reason text;

alter table public.user_profiles enable row level security;

-- user_profiles is created and managed by the server. The client may only
-- read its own row and update the existing editable profile fields.
revoke all on table public.user_profiles from anon;
revoke insert, update, delete, truncate, references, trigger
  on table public.user_profiles from authenticated;

grant select on table public.user_profiles to authenticated;
grant update (avatar_url, avatar_path, updated_at, name)
  on table public.user_profiles to authenticated;

drop policy if exists "profiles_insert_all" on public.user_profiles;
drop policy if exists "profiles_select_all" on public.user_profiles;
drop policy if exists "profiles_update_all" on public.user_profiles;
drop policy if exists "sunland_db_token_profiles" on public.user_profiles;

create policy "user_profiles_select_own"
  on public.user_profiles
  for select
  to authenticated
  using ((select auth.jwt() ->> 'id') = user_id);

create policy "user_profiles_update_own"
  on public.user_profiles
  for update
  to authenticated
  using ((select auth.jwt() ->> 'id') = user_id)
  with check ((select auth.jwt() ->> 'id') = user_id);
