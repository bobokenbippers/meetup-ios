-- ⚠️ REVIEW BEFORE APPLYING — NOT auto-applied; run manually after deciding the
-- product question below. (Migrations in this repo are applied by hand.)
--
-- Bug: share-link joins are broken. The friend-gating policy `participants_insert`
-- requires is_meetup_host(meetup_id), so a non-host joining via a share link
-- (joinByShareToken does a direct self-insert) is rejected by RLS:
--   "new row violates row-level security policy for table meetup_participants"
-- Confirmed by simulating a link-joiner's insert under their RLS context.
--
-- PRODUCT DECISION THIS ENCODES: share links let anyone (not just friends) add
-- THEMSELVES to a meetup that has sharing enabled. If you'd rather links be
-- friends-only too, do NOT apply this — the current policy already enforces that
-- (at the cost of share links not working for non-friends).
--
-- This change is purely ADDITIVE: it preserves the existing host-invite branch
-- verbatim and only adds a self-join path, so it cannot block invites that work
-- today — at most it permits the intended self-joins.
--
-- A more robust alternative (not done here): a SECURITY DEFINER RPC
-- join_meetup_by_token(token) that verifies the share_token server-side and
-- inserts, with joinByShareToken calling it instead of a direct insert. That
-- avoids letting a client self-insert into any shareable meetup it can name.

drop policy if exists participants_insert on public.meetup_participants;

create policy participants_insert on public.meetup_participants
for insert to authenticated
with check (
  -- (unchanged) host inviting an accepted friend, or adding themselves
  (is_meetup_host(meetup_id)
    AND (user_id = auth.uid() OR is_accepted_friend(auth.uid(), user_id)))
  OR
  -- (new) self-join via share link: the joiner adds only themselves, and only
  -- to a meetup that is actively shareable.
  (user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM public.meetups m
      WHERE m.id = meetup_id
        AND m.share_token IS NOT NULL
        AND m.status = 'active'
    ))
);
