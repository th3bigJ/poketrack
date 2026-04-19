-- Part A2 / Phase 1: extend profiles with V1 social identity fields

begin;

alter table public.profiles
  add column if not exists profile_roles text[] default '{}'::text[],
  add column if not exists favorite_pokemon_dex integer,
  add column if not exists favorite_pokemon_name text,
  add column if not exists favorite_pokemon_image_url text,
  add column if not exists favorite_card_id text,
  add column if not exists favorite_card_name text,
  add column if not exists favorite_card_set_code text,
  add column if not exists favorite_card_image_url text,
  add column if not exists favorite_deck_archetype text;

commit;
