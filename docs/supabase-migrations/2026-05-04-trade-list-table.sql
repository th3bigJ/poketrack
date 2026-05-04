-- Replace social_collection_items with social_trade_list_items.
-- Collections are no longer shared socially; trade lists are (cards the user is willing to trade away).
-- Safe to run multiple times.

begin;

-- Create the trade list table (mirrors wishlist shape, no quantity column).
create table if not exists public.social_trade_list_items (
    user_id uuid not null references public.profiles(id) on delete cascade,
    card_id text not null,
    variant_key text not null default 'normal',
    notes text,
    updated_at timestamptz not null default timezone('utc', now()),
    created_at timestamptz not null default timezone('utc', now()),
    primary key (user_id, card_id, variant_key)
);

create index if not exists social_trade_list_items_user_idx
    on public.social_trade_list_items(user_id);

create index if not exists social_trade_list_items_user_updated_idx
    on public.social_trade_list_items(user_id, updated_at desc);

alter table public.social_trade_list_items enable row level security;

drop policy if exists "trade_list_select_owner_or_friend" on public.social_trade_list_items;
create policy "trade_list_select_owner_or_friend"
on public.social_trade_list_items
for select
to authenticated
using (
    auth.uid() = user_id
    or exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
              (f.requester_id = auth.uid() and f.addressee_id = social_trade_list_items.user_id)
              or
              (f.addressee_id = auth.uid() and f.requester_id = social_trade_list_items.user_id)
          )
    )
);

drop policy if exists "trade_list_mutate_owner" on public.social_trade_list_items;
create policy "trade_list_mutate_owner"
on public.social_trade_list_items
for all
to authenticated
using (auth.uid() = user_id)
with check (auth.uid() = user_id);

-- Drop the old collection table (cascade cleans up policies and FK references).
drop table if exists public.social_collection_items cascade;

commit;
