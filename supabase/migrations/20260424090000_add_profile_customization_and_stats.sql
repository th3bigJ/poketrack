-- Add missing customization and collection stats columns to public.profiles
-- Reference: https://supabase.com/docs/guides/troubleshooting/refresh-postgrest-schema

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_background_color TEXT,
  ADD COLUMN IF NOT EXISTS avatar_outline_style TEXT,
  ADD COLUMN IF NOT EXISTS collection_card_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS collection_binder_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS collection_total_value NUMERIC(15,2) DEFAULT 0.00;

-- Refresh PostgREST schema cache
NOTIFY pgrst, 'reload schema';
