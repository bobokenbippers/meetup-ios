-- Let meetup participants read the basic profile fields for other people in
-- the same meetup. The dashboard embeds `profiles(display_name, phone_e164)`
-- when loading participants; if profile RLS hides the embedded row, the client
-- can fail to render the inviter/host even though the participant row exists.

drop policy if exists "meetup participants can read participant profiles" on public.profiles;

create policy "meetup participants can read participant profiles"
  on public.profiles for select
  to authenticated
  using (
    exists (
      select 1
      from public.meetup_participants mp
      where mp.user_id = profiles.id
        and public.is_meetup_participant(mp.meetup_id, auth.uid())
    )
  );
