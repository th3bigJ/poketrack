-- Split social wishlist and collection out of profiles/shared_content.
-- Safe to run multiple times.

begin;

create table if not exists public.social_wishlist_items (
    user_id uuid not null references public.profiles(id) on delete cascade,
    card_id text not null,
    variant_key text not null default 'normal',
    notes text,
    updated_at timestamptz not null default timezone('utc', now()),
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, card_id, variant_key)
);

create table if not exists public.social_collection_items (
    user_id uuid not null references public.profiles(id) on delete cascade,
    card_id text not null,
    variant_key text not null default 'normal',
    quantity integer not null default 1 check (quantity > 0),
    notes text,
    updated_at timestamptz not null default timezone('utc', now()),
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, card_id, variant_key)
);

create index if not exists social_wishlist_items_user_idx on public.social_wishlist_items(user_id);
create index if not exists social_collection_items_user_idx on public.social_collection_items(user_id);

alter table public.social_wishlist_items enable row level security;
alter table public.social_collection_items enable row level security;

drop policy if exists "wishlist_select_owner_or_friend" on public.social_wishlist_items;
create policy "wishlist_select_owner_or_friend"
on public.social_wishlist_items
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
              (f.requester_id = auth.uid() and f.addressee_id = social_wishlist_items.user_id)
              or
              (f.addressee_id = auth.uid() and f.requester_id = social_wishlist_items.user_id)
          )
    )
);

drop policy if exists "wishlist_mutate_owner" on public.social_wishlist_items;
create policy "wishlist_mutate_owner"
on public.social_wishlist_items
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

drop policy if exists "collection_select_owner_or_friend" on public.social_collection_items;
create policy "collection_select_owner_or_friend"
on public.social_collection_items
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
              (f.requester_id = auth.uid() and f.addressee_id = social_collection_items.user_id)
              or
              (f.addressee_id = auth.uid() and f.requester_id = social_collection_items.user_id)
          )
    )
);

drop policy if exists "collection_mutate_owner" on public.social_collection_items;
create policy "collection_mutate_owner"
on public.social_collection_items
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Optional one-time backfill for old profile wishlist arrays.
do $$
begin
    if exists (
        select 1
        from information_schema.columns
        where table_schema = 'public'
          and table_name = 'profiles'
          and column_name = 'wishlist_card_ids'
    ) then
        execute $backfill$
            insert into public.social_wishlist_items (user_id, card_id, variant_key, updated_at, created_at)
            select
                p.id as user_id,
                wish.card_id,
                'normal' as variant_key,
                timezone('utc', now()) as updated_at,
                timezone('utc', now()) as created_at
            from public.profiles p
            cross join lateral unnest(coalesce(p.wishlist_card_ids, array[]::text[])) as wish(card_id)
            on conflict (user_id, card_id, variant_key) do update
            set updated_at = excluded.updated_at
        $backfill$;
    end if;
end $$;

-- Remove old profile columns now that wishlist has its own table.
alter table public.profiles drop column if exists is_wishlist_public;
alter table public.profiles drop column if exists wishlist_card_ids;

-- Collection/wishlist are now sourced from dedicated tables.
delete from public.shared_content
where content_type in ('wishlist', 'collection');

commit;
