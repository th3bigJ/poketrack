-- Move social reactions to a Reddit-style upvote/downvote model.
-- Supabase docs references:
-- - https://supabase.com/docs/guides/database/tables
-- - https://supabase.com/docs/guides/database/postgres/row-level-security

alter table if exists public.reactions
  alter column reaction_type type text
  using reaction_type::text;

update public.reactions
set reaction_type = 'upvote'
where reaction_type in ('like', 'fire', 'wow');

do $$
declare
  existing_constraint record;
begin
  for existing_constraint in
    select conname
    from pg_constraint
    where conrelid = 'public.reactions'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%reaction_type%'
  loop
    execute format(
      'alter table public.reactions drop constraint if exists %I',
      existing_constraint.conname
    );
  end loop;
end
$$;

alter table if exists public.reactions
  add constraint reactions_reaction_type_check
  check (reaction_type in ('upvote', 'downvote'));
