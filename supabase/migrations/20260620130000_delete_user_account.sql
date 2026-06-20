-- Deletes all Bindr account data for a user. Intended to be called only from the
-- delete-account edge function using the service role key.

create or replace function public.delete_user_account(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_user_id is null then
    raise exception 'user id is required';
  end if;

  -- Social interactions on the user's posts
  delete from public.reactions
  where user_id = p_user_id
     or content_id in (select id from public.shared_content where owner_id = p_user_id);

  delete from public.comments
  where author_id = p_user_id
     or content_id in (select id from public.shared_content where owner_id = p_user_id);

  delete from public.wishlist_matches
  where sender_id = p_user_id
     or matcher_id = p_user_id
     or content_id in (select id from public.shared_content where owner_id = p_user_id);

  delete from public.shared_content
  where owner_id = p_user_id;

  -- Trades
  delete from public.trade_items
  where owner_id = p_user_id
     or trade_id in (
       select id from public.trades
       where initiator_id = p_user_id or receiver_id = p_user_id
     );

  delete from public.trades
  where initiator_id = p_user_id or receiver_id = p_user_id;

  delete from public.trade_sessions
  where initiator_id = p_user_id or participant_id = p_user_id;

  -- Friends + notifications
  delete from public.friendships
  where requester_id = p_user_id or addressee_id = p_user_id;

  delete from public.push_delivery_log
  where target_user_id = p_user_id;

  delete from public.device_tokens
  where user_id = p_user_id;

  delete from public.notification_preferences
  where user_id = p_user_id;

  delete from public.profiles
  where id = p_user_id;
end;
$$;

revoke all on function public.delete_user_account(uuid) from public;
grant execute on function public.delete_user_account(uuid) to service_role;
