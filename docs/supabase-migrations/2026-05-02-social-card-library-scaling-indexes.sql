-- Performance indexes for social card-library scale.
-- Supports:
-- - fast per-user reads
-- - incremental sync by updated_at
-- - friend visibility policy checks via friendships lookups

begin;

create index if not exists social_wishlist_items_user_updated_idx
    on public.social_wishlist_items (user_id, updated_at desc);

create index if not exists social_collection_items_user_updated_idx
    on public.social_collection_items (user_id, updated_at desc);

create index if not exists friendships_requester_addressee_status_idx
    on public.friendships (requester_id, addressee_id, status);

create index if not exists friendships_addressee_requester_status_idx
    on public.friendships (addressee_id, requester_id, status);

commit;
