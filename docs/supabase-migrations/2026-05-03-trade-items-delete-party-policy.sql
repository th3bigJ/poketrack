begin;

drop policy if exists "trade_items_delete_owner" on public.trade_items;
drop policy if exists "trade_items_delete_party" on public.trade_items;

create policy "trade_items_delete_party"
on public.trade_items for delete to authenticated
using (
    exists (
        select 1
        from public.trades t
        where t.id = trade_items.trade_id
          and (t.initiator_id = auth.uid() or t.receiver_id = auth.uid())
    )
);

commit;
