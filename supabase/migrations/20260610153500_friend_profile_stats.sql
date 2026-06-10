-- ============================================================
-- Friend Profile Stats
-- Aggregate attended events and punctuality counts for profile sheets.
-- ============================================================

create or replace function public.get_friend_profile_stats(p_profile_id uuid)
returns table (
  total_events  integer,
  on_time_count integer,
  late_count    integer
)
language sql
security definer
set search_path = public
as $$
  with allowed as (
    select auth.uid() = p_profile_id
      or public.is_accepted_friend(auth.uid(), p_profile_id) as can_view
  ),
  attended as (
    select
      mp.meetup_id,
      mp.arrived_at,
      m.target_arrival_at
    from public.meetup_participants mp
    join public.meetups m on m.id = mp.meetup_id
    cross join allowed a
    where a.can_view
      and mp.user_id = p_profile_id
      and (mp.status = 'arrived' or mp.arrived_at is not null)
      and m.status <> 'cancelled'
  )
  select
    count(*)::integer as total_events,
    count(*) filter (
      where target_arrival_at is not null
        and arrived_at is not null
        and arrived_at <= target_arrival_at + interval '5 minutes'
    )::integer as on_time_count,
    count(*) filter (
      where target_arrival_at is not null
        and arrived_at is not null
        and arrived_at > target_arrival_at + interval '5 minutes'
    )::integer as late_count
  from attended;
$$;

revoke all on function public.get_friend_profile_stats(uuid) from public, anon;
grant execute on function public.get_friend_profile_stats(uuid) to authenticated;
