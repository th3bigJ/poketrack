begin;

drop trigger if exists trg_push_trade_insert on public.trades;
create trigger trg_push_trade_insert
after insert on public.trades
for each row
when (new.status = 'pending')
execute function private.dispatch_social_push();

drop trigger if exists trg_push_trade_update on public.trades;
create trigger trg_push_trade_update
after update on public.trades
for each row
when (
    old.status is distinct from new.status
    or (
        new.status = 'countered'
        and (
            old.initiator_id is distinct from new.initiator_id
            or old.receiver_id is distinct from new.receiver_id
            or old.cash_initiator is distinct from new.cash_initiator
            or old.cash_receiver is distinct from new.cash_receiver
        )
    )
)
execute function private.dispatch_social_push();

commit;
