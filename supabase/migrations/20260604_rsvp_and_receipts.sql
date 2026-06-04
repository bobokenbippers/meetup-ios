-- ============================================================
-- Migration: RSVP Status + Multi-Receipt Bill Splitting
-- Date: 2026-06-04
-- ============================================================


-- ============================================================
-- Part 1: RSVP status constraint
-- Extend meetup_participants.status to include yes/no/maybe
-- ============================================================

ALTER TABLE public.meetup_participants
  DROP CONSTRAINT IF EXISTS meetup_participants_status_check;

ALTER TABLE public.meetup_participants
  ADD CONSTRAINT meetup_participants_status_check
  CHECK (status IN ('invited', 'accepted', 'yes', 'declined', 'no', 'maybe', 'arrived'));


-- ============================================================
-- Part 2: Multi-Receipt Bill Splitting
-- ============================================================

-- One receipt per place visited during a meetup
CREATE TABLE receipts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  meetup_id     uuid NOT NULL REFERENCES meetups(id) ON DELETE CASCADE,
  place_name    text NOT NULL,
  payer_user_id uuid NOT NULL REFERENCES auth.users(id),
  total_amount  numeric(10,2) NOT NULL DEFAULT 0,
  photo_url     text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

-- Allow bill_items to belong to a receipt (makes bill_id nullable)
ALTER TABLE bill_items ALTER COLUMN bill_id DROP NOT NULL;
ALTER TABLE bill_items ADD COLUMN IF NOT EXISTS receipt_id uuid REFERENCES receipts(id) ON DELETE CASCADE;

-- RLS for receipts
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "participants can read receipts"
  ON receipts FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "participants can insert receipts"
  ON receipts FOR INSERT
  WITH CHECK (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

CREATE POLICY "participants can update receipts"
  ON receipts FOR UPDATE
  USING (EXISTS (
    SELECT 1 FROM meetup_participants
    WHERE meetup_participants.meetup_id = receipts.meetup_id
      AND meetup_participants.user_id = auth.uid()
  ));

-- Update bill_items RLS policies to also allow access via receipt_id
-- (existing policies check bill_id; add receipt-based policies alongside them)

CREATE POLICY "participants can read receipt items"
  ON bill_items FOR SELECT
  USING (
    receipt_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM receipts
      JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
      WHERE receipts.id = bill_items.receipt_id
        AND meetup_participants.user_id = auth.uid()
    )
  );

CREATE POLICY "participants can insert receipt items"
  ON bill_items FOR INSERT
  WITH CHECK (
    receipt_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM receipts
      JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
      WHERE receipts.id = bill_items.receipt_id
        AND meetup_participants.user_id = auth.uid()
    )
  );

-- Update claims RLS to also cover receipt-linked items
CREATE POLICY "participants can read receipt item claims"
  ON bill_item_claims FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM bill_items
    JOIN receipts ON receipts.id = bill_items.receipt_id
    JOIN meetup_participants ON meetup_participants.meetup_id = receipts.meetup_id
    WHERE bill_items.id = bill_item_claims.bill_item_id
      AND meetup_participants.user_id = auth.uid()
  ));


-- ============================================================
-- Part 3: Storage buckets (MANUAL STEP — Supabase Dashboard)
-- ============================================================
-- The following storage buckets must be created manually in the
-- Supabase dashboard under Storage → New bucket:
--
--   * receipts       — private; stores receipt photo uploads
--   * meetup-photos  — private; for meetup event photos (future use)
--
-- After creating the buckets, configure Storage RLS policies:
--
-- For the "receipts" bucket:
--   INSERT policy:
--     (SELECT EXISTS (
--       SELECT 1 FROM receipts r
--       JOIN meetup_participants mp ON mp.meetup_id = r.meetup_id
--       WHERE r.id::text = (storage.foldername(name))[1]
--         AND mp.user_id = auth.uid()
--     ))
--   SELECT policy: same condition as INSERT
