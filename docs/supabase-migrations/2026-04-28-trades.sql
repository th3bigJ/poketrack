begin;

-- ── trades ───────────────────────────────────────────────────────────────────
create table if not exists public.trades (
    id             uuid          primary key default gen_random_uuid(),
    initiator_id   uuid          not null references public.profiles(id) on delete cascade,
    receiver_id    uuid          not null references public.profiles(id) on delete cascade,
    status         text          not null default 'pending'
                                 check (status in ('pending','countered','accepted','complete','cancelled')),
    cash_initiator numeric(10,2) not null default 0 check (cash_initiator >= 0),
    cash_receiver  numeric(10,2) not null default 0 check (cash_receiver  >= 0),
    created_at     timestamptz   not null default timezone('utc', now()),
    updated_at     timestamptz   not null default timezone('utc', now())
);

-- ── trade_items ───────────────────────────────────────────────────────────────
create table if not exists public.trade_items (
    id          uuid        primary key default gen_random_uuid(),
    trade_id    uuid        not null references public.trades(id) on delete cascade,
    owner_id    uuid        not null references public.profiles(id) on delete cascade,
    card_id     text        not null,
    variant_key text        not null default 'normal',
    quantity    integer     not null default 1 check (quantity > 0),
    created_at  timestamptz not null default timezone('utc', now())
);

-- ── indexes ───────────────────────────────────────────────────────────────────
create index if not exists trades_initiator_idx  on public.trades (initiator_id);
create index if not exists trades_receiver_idx   on public.trades (receiver_id);
create index if not exists trades_status_idx     on public.trades (status);
create index if not exists trade_items_trade_idx on public.trade_items (trade_id);
create index if not exists trade_items_owner_idx on public.trade_items (owner_id);

-- ── RLS ───────────────────────────────────────────────────────────────────────
alter table public.trades      enable row level security;
alter table public.trade_items enable row level security;

drop policy if exists "trades_select_party"       on public.trades;
drop policy if exists "trades_insert_initiator"   on public.trades;
drop policy if exists "trades_update_party"       on public.trades;
drop policy if exists "trade_items_select_party"  on public.trade_items;
drop policy if exists "trade_items_insert_party"  on public.trade_items;
drop policy if exists "trade_items_delete_owner"  on public.trade_items;

create policy "trades_select_party"
on public.trades for select to authenticated
using (auth.uid() = initiator_id or auth.uid() = receiver_id);

create policy "trades_insert_initiator"
on public.trades for insert to authenticated
with check (auth.uid() = initiator_id);

create policy "trades_update_party"
on public.trades for update to authenticated
using  (auth.uid() = initiator_id or auth.uid() = receiver_id)
with check (auth.uid() = initiator_id or auth.uid() = receiver_id);

create policy "trade_items_select_party"
on public.trade_items for select to authenticated
using (
    exists (
        select 1 from public.trades t
        where t.id = trade_items.trade_id
          and (t.initiator_id = auth.uid() or t.receiver_id = auth.uid())
    )
);

create policy "trade_items_insert_party"
on public.trade_items for insert to authenticated
with check (
    exists (
        select 1 from public.trades t
        where t.id = trade_items.trade_id
          and (t.initiator_id = auth.uid() or t.receiver_id = auth.uid())
    )
);

create policy "trade_items_delete_owner"
on public.trade_items for delete to authenticated
using (owner_id = auth.uid());

-- ── notification_preferences ──────────────────────────────────────────────────
do $$
begin
    if not exists (
        select 1 from information_schema.columns
        where table_schema = 'public'
          and table_name   = 'notification_preferences'
          and column_name  = 'trade_updates'
    ) then
        alter table public.notification_preferences
            add column trade_updates boolean not null default true;
    end if;
end $$;

commit;
