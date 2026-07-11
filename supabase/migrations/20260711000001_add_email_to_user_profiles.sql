-- 修复 /verify-code 500：public.users 已废弃（触发器阻止 INSERT），
-- 但 user_profiles 缺少 email 列，导致 email→user_id 映射无处可写。
-- 本迁移给 user_profiles 补上 email / created_at，并从旧表回填。

alter table public.user_profiles add column if not exists email text;
alter table public.user_profiles add column if not exists created_at timestamptz default now();

-- 从废弃的 users 表回填（email 统一小写）
update public.user_profiles p
set email = lower(u.email),
    created_at = coalesce(p.created_at, u.created_at)
from public.users u
where u.id = p.user_id and p.email is null;

-- email 唯一索引（防止并发注册产生重复账号）
create unique index if not exists user_profiles_email_unique_idx
  on public.user_profiles (lower(email))
  where email is not null;
