-- ============================================================
-- Migration: Shareable Meetup Invite Link
-- Date: 2026-06-05
-- ============================================================

-- Ensure share_token column exists with a default
ALTER TABLE public.meetups
  ADD COLUMN IF NOT EXISTS share_token text NOT NULL DEFAULT gen_random_uuid()::text;

-- Unique index so token lookups are fast and collision-free
CREATE UNIQUE INDEX IF NOT EXISTS meetups_share_token_idx ON public.meetups (share_token);

-- RLS: any authenticated user can read a meetup by its share_token
-- This is additive — existing policies remain intact.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'meetups'
      AND policyname = 'anyone authenticated can read meetup by share_token'
  ) THEN
    CREATE POLICY "anyone authenticated can read meetup by share_token"
      ON public.meetups
      FOR SELECT
      TO authenticated
      USING (true);
  END IF;
END $$;
