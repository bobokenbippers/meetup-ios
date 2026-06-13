-- Late punishment voting
--
-- Meetup participants who are not currently late can vote on the playful
-- "late tax" for people who missed the target arrival time. Late participants
-- are blocked in the RPC so the rule is enforced server-side, not just in UI.

create table if not exists public.meetup_late_punishment_votes (
  meetup_id  uuid        not null references public.meetups(id) on delete cascade,
  voter_id   uuid        not null references public.profiles(id) on delete cascade,
  option_key text        not null,
  created_at timestamptz not null default now(),
  primary key (meetup_id, voter_id),
  constraint meetup_late_punishment_option_check check (
    option_key in ('appetizer', 'dare', 'group_photo', 'next_spot', 'best_excuse')
  )
);

create index if not exists meetup_late_punishment_votes_meetup_idx
  on public.meetup_late_punishment_votes(meetup_id);

alter table public.meetup_late_punishment_votes enable row level security;

drop policy if exists "participants read late punishment votes"
  on public.meetup_late_punishment_votes;

create policy "participants read late punishment votes"
  on public.meetup_late_punishment_votes for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

create or replace function public.is_meetup_user_late(p_meetup_id uuid, p_user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.meetup_participants mp
    join public.meetups m on m.id = mp.meetup_id
    where mp.meetup_id = p_meetup_id
      and mp.user_id = p_user_id
      and m.status = 'active'
      and m.target_arrival_at is not null
      and now() > m.target_arrival_at
      and mp.status in ('yes', 'accepted', 'maybe', 'invited')
  );
$$;

revoke all on function public.is_meetup_user_late(uuid, uuid) from public, anon;
grant execute on function public.is_meetup_user_late(uuid, uuid) to authenticated;

create or replace function public.vote_late_punishment(p_meetup_id uuid, p_option_key text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_option_key not in ('appetizer', 'dare', 'group_photo', 'next_spot', 'best_excuse') then
    raise exception 'invalid punishment option';
  end if;

  if not (
    public.is_meetup_host(p_meetup_id)
    or public.is_meetup_participant(p_meetup_id, auth.uid())
  ) then
    raise exception 'only meetup participants can vote';
  end if;

  if public.is_meetup_user_late(p_meetup_id, auth.uid()) then
    raise exception 'late participants cannot vote on their punishment';
  end if;

  insert into public.meetup_late_punishment_votes (meetup_id, voter_id, option_key)
  values (p_meetup_id, auth.uid(), p_option_key)
  on conflict (meetup_id, voter_id)
  do update set option_key = excluded.option_key, created_at = now();
end;
$$;

revoke all on function public.vote_late_punishment(uuid, text) from public, anon;
grant execute on function public.vote_late_punishment(uuid, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.meetup_late_punishment_votes;
exception
  when duplicate_object then null;
end $$;
