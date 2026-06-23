-- ============================================================
-- Migration: Push notification token consistency
-- Date: 2026-06-23
-- ============================================================
--
-- Context:
--   - profiles.apns_token: primary field, read by push-meetup-invite,
--     push-meetup-status, push-friend-request, push-new-message,
--     push-meetup-cancelled, push-game-group-start, push-rsvp-update,
--     and push-leave-now.
--   - device_tokens: secondary per-device registry, populated by
--     NotificationService.registerDeviceToken on the iOS side.
--   - The apns.ts shared module now clears both tables on APNs 410
--     (stale token) responses.
--
-- This migration adds a helper function for ops/edge-function manual cleanup
-- when a stale token is discovered outside the shared module.

create or replace function public.clear_stale_apns_token(p_token text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.profiles
     set apns_token = null,
         updated_at = now()
   where apns_token = p_token;

  delete from public.device_tokens
   where token = p_token;
end;
$$;

revoke all on function public.clear_stale_apns_token(text) from public, anon, authenticated;
grant execute on function public.clear_stale_apns_token(text) to service_role;
