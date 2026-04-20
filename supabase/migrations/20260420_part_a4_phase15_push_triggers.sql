-- Part A4 Phase 15: push dispatch via Edge Function + database triggers
-- References:
-- - https://supabase.com/docs/guides/database/webhooks
-- - https://supabase.com/docs/guides/database/extensions/pg_net

create extension if not exists pg_net;

create schema if not exists private;

create table if not exists public.push_delivery_log (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  target_user_id uuid references public.profiles(id) on delete set null,
  device_token text,
  payload jsonb not null default '{}'::jsonb,
  status text not null check (status in ('sent', 'skipped', 'failed')),
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists push_delivery_log_event_idx on public.push_delivery_log (event_type);
create index if not exists push_delivery_log_created_idx on public.push_delivery_log (created_at desc);

alter table public.push_delivery_log enable row level security;

drop policy if exists "push_delivery_log_no_client_access" on public.push_delivery_log;
create policy "push_delivery_log_no_client_access"
on public.push_delivery_log
for all
to authenticated
using (false)
with check (false);

create or replace function private.dispatch_social_push()
returns trigger
language plpgsql
security definer
set search_path = public, private, net
as $$
declare
  target_url text := 'https://eovjwogsniwfwxfrtoer.supabase.co/functions/v1/social-push';
  target_headers jsonb := jsonb_build_object(
    'Content-Type', 'application/json',
    'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVvdmp3b2dzbml3Znd4ZnJ0b2VyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY0NDYwNzIsImV4cCI6MjA5MjAyMjA3Mn0.lbUTIhoKVpSyOfysmVrlsw-FnVzt6DuMaUVK_FyF8w0'
  );
  payload jsonb;
begin
  if tg_op = 'INSERT' then
    payload := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', null
    );
  elsif tg_op = 'UPDATE' then
    payload := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', to_jsonb(new),
      'old_record', to_jsonb(old)
    );
  else
    payload := jsonb_build_object(
      'type', tg_op,
      'table', tg_table_name,
      'schema', tg_table_schema,
      'record', null,
      'old_record', to_jsonb(old)
    );
  end if;

  perform net.http_post(
    url := target_url,
    body := payload,
    params := '{}'::jsonb,
    headers := target_headers,
    timeout_milliseconds := 2000
  );

  return coalesce(new, old);
end;
$$;

drop trigger if exists trg_push_friendship_insert on public.friendships;
create trigger trg_push_friendship_insert
after insert on public.friendships
for each row
when (new.status = 'pending')
execute function private.dispatch_social_push();

drop trigger if exists trg_push_friendship_accept on public.friendships;
create trigger trg_push_friendship_accept
after update on public.friendships
for each row
when (old.status is distinct from new.status and new.status = 'accepted')
execute function private.dispatch_social_push();

drop trigger if exists trg_push_shared_content_insert on public.shared_content;
create trigger trg_push_shared_content_insert
after insert on public.shared_content
for each row
execute function private.dispatch_social_push();

drop trigger if exists trg_push_comment_insert on public.comments;
create trigger trg_push_comment_insert
after insert on public.comments
for each row
execute function private.dispatch_social_push();

drop trigger if exists trg_push_wishlist_match_insert on public.wishlist_matches;
create trigger trg_push_wishlist_match_insert
after insert on public.wishlist_matches
for each row
execute function private.dispatch_social_push();
