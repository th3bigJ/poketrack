-- Trade list has been removed from the app. The collection is now the source
-- of truth for trades; collection snapshots are stored in R2 instead.

drop table if exists public.social_trade_list_items;
