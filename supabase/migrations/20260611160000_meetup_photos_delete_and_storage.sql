-- Meetup photo gallery: deletion + storage hardening
--
-- 1. Tighten who can add photos: only active participants (accepted /
--    arrived / legacy 'yes') or the host. The original policy let any
--    participant row — including invited and declined users — insert.
-- 2. Let the meetup host delete any photo in their meetup; uploaders can
--    still delete their own.
-- 3. Move the meetup-photos storage bucket + object RLS out of
--    dashboard-only comments (20260605020000_meetup_photos.sql) into SQL,
--    scoped by the <meetup_id>/ path prefix.
--
-- NOTE: if permissive "any authenticated user" policies were previously
-- created for the meetup-photos bucket via the Supabase Dashboard, remove
-- them there — these named policies do not replace dashboard-created ones.

-- Helper: participant whose RSVP makes them an active member of the meetup.
create or replace function public.is_active_meetup_participant(p_meetup_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.meetup_participants mp
    where mp.meetup_id = p_meetup_id
      and mp.user_id = p_user_id
      and mp.status in ('accepted', 'arrived', 'yes')
  );
$$;

revoke all on function public.is_active_meetup_participant(uuid, uuid) from public, anon;
grant execute on function public.is_active_meetup_participant(uuid, uuid) to authenticated;

-- ============================================================
-- meetup_photos table policies
-- ============================================================

drop policy if exists "participants can insert meetup photos" on public.meetup_photos;
create policy "participants can insert meetup photos"
  on public.meetup_photos for insert
  to authenticated
  with check (
    uploader_user_id = auth.uid()
    and (
      public.is_meetup_host(meetup_id)
      or public.is_active_meetup_participant(meetup_id, auth.uid())
    )
  );

drop policy if exists "uploaders can delete own photos" on public.meetup_photos;
drop policy if exists "uploaders and hosts can delete photos" on public.meetup_photos;
create policy "uploaders and hosts can delete photos"
  on public.meetup_photos for delete
  to authenticated
  using (
    uploader_user_id = auth.uid()
    or public.is_meetup_host(meetup_id)
  );

-- ============================================================
-- Storage bucket: meetup-photos (private, signed-URL reads)
-- ============================================================

insert into storage.buckets (id, name, public)
values ('meetup-photos', 'meetup-photos', false)
on conflict (id) do nothing;

-- Files are stored at <meetup_id>/<uuid>.jpg, so every policy scopes by
-- the first path segment (same pattern as the message-photos bucket).

drop policy if exists "participants read meetup photos" on storage.objects;
create policy "participants read meetup photos"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'meetup-photos'
    and (
      public.is_meetup_host((storage.foldername(name))[1]::uuid)
      or public.is_meetup_participant((storage.foldername(name))[1]::uuid, auth.uid())
    )
  );

drop policy if exists "participants upload meetup photos" on storage.objects;
create policy "participants upload meetup photos"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'meetup-photos'
    and (
      public.is_meetup_host((storage.foldername(name))[1]::uuid)
      or public.is_active_meetup_participant((storage.foldername(name))[1]::uuid, auth.uid())
    )
  );

drop policy if exists "uploaders and hosts delete meetup photos" on storage.objects;
create policy "uploaders and hosts delete meetup photos"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'meetup-photos'
    and (
      owner = auth.uid()
      or public.is_meetup_host((storage.foldername(name))[1]::uuid)
    )
  );
