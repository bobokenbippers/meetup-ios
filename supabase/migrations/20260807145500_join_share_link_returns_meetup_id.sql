-- Share-link joins should behave like a real join: return the meetup id so the
-- client can navigate there, and mark the caller as going.

create or replace function public.join_meetup_by_token(p_share_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meetup_id uuid;
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'not signed in' using errcode = '28000';
  end if;

  select id
    into v_meetup_id
  from public.meetups
  where share_token = p_share_token
    and status = 'active'
  limit 1;

  if v_meetup_id is null then
    raise exception 'meetup not found' using errcode = 'P0002';
  end if;

  insert into public.meetup_participants (meetup_id, user_id, status, joined_at)
  values (v_meetup_id, v_user_id, 'yes', now())
  on conflict (meetup_id, user_id) do update
    set status = 'yes',
        joined_at = coalesce(public.meetup_participants.joined_at, now());

  return v_meetup_id;
end;
$$;

revoke all on function public.join_meetup_by_token(text) from public;
grant execute on function public.join_meetup_by_token(text) to authenticated;
