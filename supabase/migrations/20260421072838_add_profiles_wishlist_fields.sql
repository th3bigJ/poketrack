-- Add wishlist privacy/settings columns used by iOS profile upsert payloads.
-- Reference: https://supabase.com/docs/guides/troubleshooting/refresh-postgrest-schema

alter table public.profiles
  add column if not exists is_wishlist_public boolean not null default false,
  add column if not exists wishlist_card_ids text[] not null default '{}'::text[];

notify pgrst, 'reload schema';
