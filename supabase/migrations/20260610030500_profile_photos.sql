-- Profile photos
--
-- Stores the current public avatar URL on profiles and keeps image uploads
-- scoped to each user's own folder in the profile-photos bucket.

alter table public.profiles
  add column if not exists email text,
  add column if not exists avatar_url text;

create or replace function public.is_accepted_friend(p_host_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.friendships f
    where f.status = 'accepted'
      and (
        (f.user_a_id = p_host_id and f.user_b_id = p_user_id)
        or
        (f.user_b_id = p_host_id and f.user_a_id = p_user_id)
      )
  );
$$;

revoke all on function public.is_accepted_friend(uuid, uuid) from public, anon;
grant execute on function public.is_accepted_friend(uuid, uuid) to authenticated;

drop policy if exists "accepted friends can read profiles" on public.profiles;
create policy "accepted friends can read profiles"
  on public.profiles for select
  to authenticated
  using (
    auth.uid() = id
    or public.is_accepted_friend(auth.uid(), profiles.id)
  );

insert into storage.buckets (id, name, public)
values ('profile-photos', 'profile-photos', true)
on conflict (id) do update set public = true;

drop policy if exists "anyone can read profile photos" on storage.objects;
create policy "anyone can read profile photos"
  on storage.objects for select
  using (bucket_id = 'profile-photos');

drop policy if exists "users upload own profile photos" on storage.objects;
create policy "users upload own profile photos"
  on storage.objects for insert
  with check (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "users update own profile photos" on storage.objects;
create policy "users update own profile photos"
  on storage.objects for update
  using (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  )
  with check (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

drop policy if exists "users delete own profile photos" on storage.objects;
create policy "users delete own profile photos"
  on storage.objects for delete
  using (
    bucket_id = 'profile-photos'
    and auth.uid()::text = (storage.foldername(name))[1]
  );

-- Search RPCs include avatar_url so add-friend and invite flows can render
-- real profile photos as soon as a user is found.
drop function if exists public.find_user_by_phone(text);
create function public.find_user_by_phone(search_phone text)
returns table (id uuid, display_name text, phone_e164 text, avatar_url text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.phone_e164, p.avatar_url
  from public.profiles p
  where p.phone_e164 = search_phone
  limit 1;
$$;

revoke all on function public.find_user_by_phone(text) from public, anon;
grant execute on function public.find_user_by_phone(text) to authenticated;

drop function if exists public.find_user_by_email(text);
create function public.find_user_by_email(search_email text)
returns table (id uuid, display_name text, phone_e164 text, avatar_url text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.display_name, p.phone_e164, p.avatar_url
  from public.profiles p
  where lower(p.email) = lower(search_email)
  limit 1;
$$;

revoke all on function public.find_user_by_email(text) from public, anon;
grant execute on function public.find_user_by_email(text) to authenticated;

-- Refresh the participant RPC shape so meetup dashboards can show avatars.
drop function if exists public.list_meetup_participants(uuid);
create function public.list_meetup_participants(p_meetup_id uuid)
returns table (
  meetup_id uuid,
  user_id uuid,
  status text,
  lat double precision,
  lng double precision,
  bearing double precision,
  eta_seconds int,
  location_updated_at timestamptz,
  display_name text,
  phone_e164 text,
  avatar_url text
)
language sql
security definer
set search_path = public
as $$
  select
    mp.meetup_id,
    mp.user_id,
    mp.status,
    mp.lat,
    mp.lng,
    mp.bearing,
    mp.eta_seconds,
    mp.location_updated_at,
    p.display_name,
    p.phone_e164,
    p.avatar_url
  from public.meetup_participants mp
  join public.profiles p on p.id = mp.user_id
  join public.meetups m on m.id = mp.meetup_id
  where mp.meetup_id = p_meetup_id
    and (
      public.is_meetup_host(p_meetup_id)
      or public.is_meetup_participant(p_meetup_id, auth.uid())
    )
  order by
    case
      when mp.user_id = m.host_id then 0
      when mp.user_id = auth.uid() then 1
      else 2
    end,
    p.display_name;
$$;

revoke all on function public.list_meetup_participants(uuid) from public, anon;
grant execute on function public.list_meetup_participants(uuid) to authenticated;
