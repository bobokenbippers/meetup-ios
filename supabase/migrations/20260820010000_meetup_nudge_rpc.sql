create or replace function public.nudge_meetup_participant(p_meetup_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_host_id uuid := auth.uid();
  v_target_status text;
begin
  if v_host_id is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  if not exists (
    select 1
    from public.meetups m
    where m.id = p_meetup_id
      and m.host_id = v_host_id
  ) then
    raise exception 'only the meetup host can send nudges' using errcode = '42501';
  end if;

  select mp.status
    into v_target_status
  from public.meetup_participants mp
  where mp.meetup_id = p_meetup_id
    and mp.user_id = p_user_id
  limit 1;

  if v_target_status is null then
    raise exception 'participant not found' using errcode = 'P0002';
  end if;

  if v_target_status <> 'invited' then
    raise exception 'only invited participants can be nudged' using errcode = 'P0001';
  end if;

  perform public.call_push_function(
    'push-meetup-nudge',
    jsonb_build_object('meetupId', p_meetup_id, 'userId', p_user_id)
  );
end;
$$;

revoke all on function public.nudge_meetup_participant(uuid, uuid) from public, anon;
grant execute on function public.nudge_meetup_participant(uuid, uuid) to authenticated;
