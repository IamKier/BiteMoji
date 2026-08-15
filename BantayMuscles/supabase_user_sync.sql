-- Per-user cloud sync for BiteMoji.
-- Run once in the Supabase SQL Editor. Idempotent — safe to re-run.
--
-- Stores one JSON snapshot per user — whatever AppStore.exportData() writes
-- (profile, diary, steps, weights, saved foods, and deletion tombstones).
-- It's a single jsonb column, so adding fields to the snapshot needs no
-- migration here.
-- Row-level security is what keeps each user's data private, since the app
-- ships a publishable key. Without these policies, data would be exposed.

create table if not exists public.user_data (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz not null default now()
);

alter table public.user_data enable row level security;

-- Each signed-in user may touch ONLY their own row (auth.uid() = user_id).
drop policy if exists "user_data select own" on public.user_data;
create policy "user_data select own" on public.user_data
  for select using (auth.uid() = user_id);

drop policy if exists "user_data insert own" on public.user_data;
create policy "user_data insert own" on public.user_data
  for insert with check (auth.uid() = user_id);

drop policy if exists "user_data update own" on public.user_data;
create policy "user_data update own" on public.user_data
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
