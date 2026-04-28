-- 2026-04-28 — Reactions table: switch CHECK constraint to upvote/downvote.
--
-- The original schema (see docs/bindr-product-build-plan.md) defined the
-- reactions table with `check (reaction_type in ('like','fire','wow'))`. The
-- iOS client has since moved to a simple upvote/downvote model
-- (`ReactionType` in Bindr/Models/SocialModels.swift), so every POST to
-- /rest/v1/reactions sends `reaction_type = 'upvote' | 'downvote'` and the
-- old CHECK rejects it with:
--
--   new row for relation "reactions" violates check constraint
--   "reactions_reaction_type_check"
--
-- Run this in the Supabase SQL editor against the project the iOS app talks
-- to. Safe to run multiple times — the DROP IF EXISTS makes it idempotent.

alter table public.reactions
    drop constraint if exists reactions_reaction_type_check;

alter table public.reactions
    add constraint reactions_reaction_type_check
    check (reaction_type in ('upvote', 'downvote'));

-- If any historical rows still hold legacy values, normalise them to upvotes
-- so they remain valid under the new constraint. Comment this out if you'd
-- rather delete those rows instead.
update public.reactions
set reaction_type = 'upvote'
where reaction_type not in ('upvote', 'downvote');
