-- Fix participant visibility for invited users.
--
-- Invited users need to see every participant in the meetup, including the host.
-- Keep the RLS policy itself free of direct self-recursive table scans by moving
-- membership checks into SECURITY DEFINER helpers.

create or replace function public.is_meetup_participant(p_meetup_id uuid, p_user_id uuid)
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
  );
$$;

revoke all on function public.is_meetup_participant(uuid, uuid) from public, anon;
grant execute on function public.is_meetup_participant(uuid, uuid) to authenticated;

drop policy if exists "see participants of meetups you're in" on public.meetup_participants;
drop policy if exists participants_select on public.meetup_participants;

create policy participants_select
  on public.meetup_participants for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

-- Older/broken creates may have produced an invitee row without the host row.
-- Backfill those so the dashboard always has an inviter/host participant to render.
insert into public.meetup_participants (meetup_id, user_id, status, joined_at)
select m.id, m.host_id, 'yes', coalesce(m.created_at, now())
from public.meetups m
where not exists (
  select 1
  from public.meetup_participants mp
  where mp.meetup_id = m.id
    and mp.user_id = m.host_id
)
on conflict (meetup_id, user_id) do nothing;

create or replace function public.list_meetup_participants(p_meetup_id uuid)
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
  phone_e164 text
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
    p.phone_e164
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
