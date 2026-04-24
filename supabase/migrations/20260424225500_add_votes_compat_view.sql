-- Compatibility layer for renaming social "reactions" -> "votes" without breaking clients.
-- References:
-- - https://supabase.com/docs/guides/database/tables
-- - https://supabase.com/docs/guides/database/postgres/row-level-security
-- - https://www.postgresql.org/docs/current/sql-createview.html

drop view if exists public.votes;

create view public.votes
with (security_invoker = true)
as
select
  id,
  content_id,
  user_id,
  reaction_type as vote_direction,
  created_at
from public.reactions;

comment on view public.votes is
  'Compatibility view over public.reactions using vote naming (vote_direction).';

comment on column public.votes.vote_direction is
  'Alias of public.reactions.reaction_type. Values: upvote, downvote.';

grant select, insert, update, delete on public.votes to authenticated;
