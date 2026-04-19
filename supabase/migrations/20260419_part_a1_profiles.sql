-- Part A1 / Phase 1: profiles + notification preferences + device tokens
-- Safe to re-run in development because policies are recreated idempotently.

begin;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  apple_user_id text unique not null,
  username text unique not null,
  display_name text,
  avatar_url text,
  bio text,
  pinned_card_id text,
  created_at timestamptz default now()
);

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  friend_requests boolean default true,
  friend_accepts boolean default true,
  shared_content_posts boolean default true,
  comments boolean default true,
  wishlist_matches boolean default true,
  trade_updates boolean default true,
  marketing boolean default false,
  updated_at timestamptz default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  token text not null,
  updated_at timestamptz default now(),
  unique(user_id, token)
);

alter table public.profiles enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_tokens enable row level security;

-- profiles: any authenticated user can read, owner can mutate own row
drop policy if exists "profiles_auth_read" on public.profiles;
create policy "profiles_auth_read"
  on public.profiles
  for select
  to authenticated
  using (true);

drop policy if exists "profiles_owner_insert" on public.profiles;
create policy "profiles_owner_insert"
  on public.profiles
  for insert
  to authenticated
  with check ((select auth.uid()) = id);

drop policy if exists "profiles_owner_update" on public.profiles;
create policy "profiles_owner_update"
  on public.profiles
  for update
  to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "profiles_owner_delete" on public.profiles;
create policy "profiles_owner_delete"
  on public.profiles
  for delete
  to authenticated
  using ((select auth.uid()) = id);

-- notification_preferences: owner-only access
drop policy if exists "notification_prefs_owner_select" on public.notification_preferences;
create policy "notification_prefs_owner_select"
  on public.notification_preferences
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "notification_prefs_owner_insert" on public.notification_preferences;
create policy "notification_prefs_owner_insert"
  on public.notification_preferences
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "notification_prefs_owner_update" on public.notification_preferences;
create policy "notification_prefs_owner_update"
  on public.notification_preferences
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "notification_prefs_owner_delete" on public.notification_preferences;
create policy "notification_prefs_owner_delete"
  on public.notification_preferences
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

-- device_tokens: owner-only access
drop policy if exists "device_tokens_owner_select" on public.device_tokens;
create policy "device_tokens_owner_select"
  on public.device_tokens
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "device_tokens_owner_insert" on public.device_tokens;
create policy "device_tokens_owner_insert"
  on public.device_tokens
  for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "device_tokens_owner_update" on public.device_tokens;
create policy "device_tokens_owner_update"
  on public.device_tokens
  for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "device_tokens_owner_delete" on public.device_tokens;
create policy "device_tokens_owner_delete"
  on public.device_tokens
  for delete
  to authenticated
  using ((select auth.uid()) = user_id);

commit;
