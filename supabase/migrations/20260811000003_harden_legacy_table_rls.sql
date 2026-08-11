alter table public.activation_codes enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
alter table public.usage enable row level security;

-- Activation codes are claimed by the Worker with service_role. Legacy
-- clients must not enumerate or mutate codes directly.
revoke all on table public.activation_codes from public, anon, authenticated;

-- Conversations remain client-synced, but only through the short-lived
-- authenticated database token and only for the token owner.
revoke all on table public.conversations from public, anon, authenticated;
grant select, insert, update, delete
  on table public.conversations to authenticated;

-- This legacy messages table is no longer used by the Flutter client.
revoke all on table public.messages from public, anon, authenticated;

-- Usage is server-managed; the client only displays its own count.
revoke all on table public.usage from public, anon, authenticated;
grant select on table public.usage to authenticated;

drop policy if exists "activation_codes_read" on public.activation_codes;
drop policy if exists "allow update own code" on public.activation_codes;
drop policy if exists "anyone can read unused codes" on public.activation_codes;
drop policy if exists "user can claim code" on public.activation_codes;

drop policy if exists "conversations_self" on public.conversations;
drop policy if exists "sunland_db_token_conversations" on public.conversations;
drop policy if exists "users_delete_own_conversations" on public.conversations;
drop policy if exists "users_insert_own_conversations" on public.conversations;
drop policy if exists "users_select_own_conversations" on public.conversations;
drop policy if exists "users_update_own_conversations" on public.conversations;

drop policy if exists "Users can access their messages" on public.messages;

drop policy if exists "sunland_db_token_usage" on public.usage;
drop policy if exists "usage_self" on public.usage;
drop policy if exists "users_insert_own_usage" on public.usage;
drop policy if exists "users_select_own_usage" on public.usage;
drop policy if exists "users_update_own_usage" on public.usage;

create policy "conversations_authenticated_own"
  on public.conversations
  for all
  to authenticated
  using ((select auth.jwt() ->> 'id') = user_id)
  with check ((select auth.jwt() ->> 'id') = user_id);

create policy "usage_authenticated_read_own"
  on public.usage
  for select
  to authenticated
  using ((select auth.jwt() ->> 'id') = user_id);
