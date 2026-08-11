create table if not exists public.app_config (
  config_key text primary key,
  maintenance_enabled boolean not null default false,
  maintenance_title text not null default '服务器维护中',
  maintenance_message text not null default '服务器正在进行维护，请稍后再试。',
  maintenance_estimated_end timestamptz,
  updated_at timestamptz not null default now(),
  constraint app_config_global_only check (config_key = 'global')
);

alter table public.app_config enable row level security;

revoke all on table public.app_config from public, anon, authenticated;
grant select on table public.app_config to anon, authenticated;

drop policy if exists "app_config_read_global" on public.app_config;

create policy "app_config_read_global"
  on public.app_config
  for select
  to anon, authenticated
  using (config_key = 'global');

insert into public.app_config (
  config_key,
  maintenance_enabled,
  maintenance_title,
  maintenance_message
)
values (
  'global',
  false,
  '服务器维护中',
  '服务器正在进行维护，请稍后再试。'
)
on conflict (config_key) do nothing;
