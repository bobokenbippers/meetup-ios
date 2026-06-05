-- ============================================================
-- Migration: APNs push notification columns on profiles
-- Date: 2026-06-04
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS apns_token   text,
  ADD COLUMN IF NOT EXISTS apns_sandbox boolean NOT NULL DEFAULT true;
