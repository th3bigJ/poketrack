-- Fix infinite recursion in friendships INSERT RLS policy.
-- The previous policy queried public.friendships directly in WITH CHECK,
-- which can recurse under RLS evaluation.

create schema if not exists private;

create or replace function private.friendship_pair_blocked(a uuid, b uuid)
returns boolean
language sql
security definer
set search_path = public, pg_catalog
as $$
  select exists (
    select 1
    from public.friendships f
    where (
      (f.requester_id = a and f.addressee_id = b)
      or (f.requester_id = b and f.addressee_id = a)
    )
      and f.status = 'blocked'
  );
$$;

revoke all on function private.friendship_pair_blocked(uuid, uuid) from public;
grant execute on function private.friendship_pair_blocked(uuid, uuid) to authenticated;

drop policy if exists friendships_insert_requester_only on public.friendships;
create policy friendships_insert_requester_only
on public.friendships
for insert
to authenticated
with check (
  auth.uid() = requester_id
  and requester_id <> addressee_id
  and not private.friendship_pair_blocked(requester_id, addressee_id)
);
