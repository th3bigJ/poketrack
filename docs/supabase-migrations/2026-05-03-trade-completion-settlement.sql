-- Settle social collection inventory when a trade is marked complete.
-- Runs exactly once per trade, and only when status transitions to `complete`.

begin;

create table if not exists public.trade_settlements (
    trade_id uuid primary key references public.trades(id) on delete cascade,
    settled_at timestamptz not null default timezone('utc', now()),
    settled_by uuid references public.profiles(id) on delete set null
);

alter table public.trade_settlements enable row level security;

drop policy if exists "trade_settlements_select_party" on public.trade_settlements;
create policy "trade_settlements_select_party"
on public.trade_settlements for select to authenticated
using (
    exists (
        select 1
        from public.trades t
        where t.id = trade_settlements.trade_id
          and (t.initiator_id = auth.uid() or t.receiver_id = auth.uid())
    )
);

create or replace function public.enforce_trade_completion_transition()
returns trigger
language plpgsql
as $$
begin
    -- Completion is only valid after acceptance.
    if new.status = 'complete' and old.status <> 'accepted' then
        raise exception 'Trade can only be completed from accepted status.';
    end if;

    -- Do not allow reopening / mutating after completion.
    if old.status = 'complete' and new.status <> 'complete' then
        raise exception 'Completed trades are immutable.';
    end if;

    return new;
end;
$$;

drop trigger if exists trg_enforce_trade_completion_transition on public.trades;
create trigger trg_enforce_trade_completion_transition
before update of status on public.trades
for each row
execute function public.enforce_trade_completion_transition();

create or replace function public.apply_trade_settlement(
    p_trade_id uuid,
    p_settled_by uuid default auth.uid()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
    v_initiator_id uuid;
    v_receiver_id uuid;
begin
    -- Guard against duplicate settlement runs.
    if exists (select 1 from public.trade_settlements ts where ts.trade_id = p_trade_id) then
        return;
    end if;

    select t.initiator_id, t.receiver_id
    into v_initiator_id, v_receiver_id
    from public.trades t
    where t.id = p_trade_id;

    if v_initiator_id is null or v_receiver_id is null then
        raise exception 'Trade % not found for settlement.', p_trade_id;
    end if;

    -- Debit cards from each owner's shared collection.
    update public.social_collection_items sci
    set
        quantity = sci.quantity - src.total_qty,
        updated_at = timezone('utc', now())
    from (
        select
            ti.owner_id,
            ti.card_id,
            ti.variant_key,
            sum(ti.quantity)::integer as total_qty
        from public.trade_items ti
        where ti.trade_id = p_trade_id
        group by ti.owner_id, ti.card_id, ti.variant_key
    ) as src
    where sci.user_id = src.owner_id
      and sci.card_id = src.card_id
      and sci.variant_key = src.variant_key;

    -- Remove rows that reached zero (or below, as defensive cleanup).
    delete from public.social_collection_items
    where user_id in (v_initiator_id, v_receiver_id)
      and quantity <= 0;

    -- Credit cards to the counterparty.
    insert into public.social_collection_items (
        user_id,
        card_id,
        variant_key,
        quantity,
        notes,
        updated_at,
        created_at
    )
    select
        case
            when src.owner_id = v_initiator_id then v_receiver_id
            when src.owner_id = v_receiver_id then v_initiator_id
            else null
        end as user_id,
        src.card_id,
        src.variant_key,
        src.total_qty,
        null as notes,
        timezone('utc', now()) as updated_at,
        timezone('utc', now()) as created_at
    from (
        select
            ti.owner_id,
            ti.card_id,
            ti.variant_key,
            sum(ti.quantity)::integer as total_qty
        from public.trade_items ti
        where ti.trade_id = p_trade_id
        group by ti.owner_id, ti.card_id, ti.variant_key
    ) as src
    where src.owner_id in (v_initiator_id, v_receiver_id)
    on conflict (user_id, card_id, variant_key)
    do update
    set
        quantity = social_collection_items.quantity + excluded.quantity,
        updated_at = excluded.updated_at;

    insert into public.trade_settlements (trade_id, settled_by)
    values (p_trade_id, p_settled_by)
    on conflict (trade_id) do nothing;

    return;
end;
$$;

create or replace function public.settle_trade_inventory_on_complete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
    perform public.apply_trade_settlement(new.id, auth.uid());
    return new;
end;
$$;

drop trigger if exists trg_settle_trade_inventory_on_complete on public.trades;
create trigger trg_settle_trade_inventory_on_complete
after update of status on public.trades
for each row
when (new.status = 'complete' and old.status is distinct from new.status)
execute function public.settle_trade_inventory_on_complete();

-- Backfill safety: if any trades were already complete before this migration,
-- settle them now (once).
do $$
declare
    r record;
begin
    for r in
        select t.id
        from public.trades t
        where t.status = 'complete'
          and not exists (
              select 1
              from public.trade_settlements ts
              where ts.trade_id = t.id
          )
    loop
        perform public.apply_trade_settlement(r.id, null);
    end loop;
end
$$;

commit;
