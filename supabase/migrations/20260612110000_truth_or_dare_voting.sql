-- ============================================================
-- Truth or Dare: squad vote on turn completion
--
-- Completing a turn no longer takes the player's word for it.
-- "Done" (truth answered / dare proof posted) now moves the turn
-- into a `voting` state instead of completing it. The OTHER
-- players in the session vote counts / doesn't count:
--
--   * a strict majority of yes votes (> half of eligible voters)
--     completes the turn;
--   * as soon as a yes majority is mathematically impossible
--     (ties included), the turn is marked `failed` and penalized
--     on the scoreboard exactly like a chicken-out.
--
-- Eligible voters are the session's players minus the turn's
-- player. Votes are written through a SECURITY DEFINER RPC and
-- sync over Realtime like the rest of the game state. Chickening
-- out (`pass`) still skips voting entirely.
-- ============================================================

-- New turn states: voting (verdict pending) and failed (voted out).
alter table public.game_turns drop constraint if exists game_turns_status_check;

alter table public.game_turns add constraint game_turns_status_check
  check (status in ('pending', 'prompted', 'voting', 'completed', 'passed', 'failed'));

-- ------------------------------------------------------------
-- Votes
-- ------------------------------------------------------------

create table if not exists public.game_turn_votes (
  turn_id     uuid        not null references public.game_turns(id) on delete cascade,
  voter_id    uuid        not null references public.profiles(id) on delete cascade,
  vote        boolean     not null,  -- true = counts, false = doesn't count
  created_at  timestamptz not null default now(),
  primary key (turn_id, voter_id)
);

create index if not exists game_turn_votes_turn_idx on public.game_turn_votes(turn_id);

alter table public.game_turn_votes enable row level security;

drop policy if exists "participants read turn votes" on public.game_turn_votes;

create policy "participants read turn votes"
  on public.game_turn_votes for select
  to authenticated
  using (
    exists (
      select 1
      from public.game_turns gt
      join public.game_sessions gs on gs.id = gt.session_id
      where gt.id = turn_id
        and (
          public.is_meetup_host(gs.meetup_id)
          or public.is_meetup_participant(gs.meetup_id, auth.uid())
        )
    )
  );

-- ------------------------------------------------------------
-- Internal helper: advance the loop to the next player
-- Callers must hold the row locks; not exposed to clients.
-- ------------------------------------------------------------

create or replace function public.advance_truth_or_dare_turn(
  p_session_id           uuid,
  p_finished_turn_number integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session     public.game_sessions%rowtype;
  v_count       integer;
  v_next_index  integer;
  v_next_player uuid;
begin
  select * into v_session
  from public.game_sessions
  where id = p_session_id
  for update;

  v_count := array_length(v_session.turn_order, 1);
  v_next_index := v_session.current_turn_index + 1;
  v_next_player := v_session.turn_order[(v_next_index % v_count) + 1];

  update public.game_sessions
  set current_turn_index = v_next_index
  where id = p_session_id;

  insert into public.game_turns (session_id, turn_number, player_id)
  values (p_session_id, p_finished_turn_number + 1, v_next_player);
end;
$$;

revoke all on function public.advance_truth_or_dare_turn(uuid, integer) from public, anon, authenticated;

-- ------------------------------------------------------------
-- RPC: complete or pass the current turn
-- `done` now opens the squad vote instead of completing; only
-- `pass` (chicken out) still resolves and advances immediately.
-- ------------------------------------------------------------

create or replace function public.complete_truth_or_dare_turn(
  p_turn_id    uuid,
  p_action     text,
  p_proof_path text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn    public.game_turns%rowtype;
  v_session public.game_sessions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_action not in ('done', 'pass') then
    raise exception 'invalid action';
  end if;

  select * into v_turn
  from public.game_turns
  where id = p_turn_id
  for update;

  if not found then
    raise exception 'turn not found';
  end if;

  if v_turn.player_id <> auth.uid() then
    raise exception 'not your turn';
  end if;

  if v_turn.status <> 'prompted' then
    raise exception 'flip the coin first';
  end if;

  if p_action = 'done' and v_turn.prompt_kind = 'dare'
     and (p_proof_path is null or length(trim(p_proof_path)) = 0) then
    raise exception 'a dare needs a proof photo';
  end if;

  select * into v_session
  from public.game_sessions
  where id = v_turn.session_id
  for update;

  if v_session.status <> 'active' then
    raise exception 'game is not active';
  end if;

  if p_action = 'pass' then
    update public.game_turns
    set status = 'passed',
        completed_at = now()
    where id = p_turn_id;

    perform public.advance_truth_or_dare_turn(v_session.id, v_turn.turn_number);
  else
    -- The squad decides whether it counts; the turn (and the loop)
    -- waits in `voting` until the vote resolves.
    update public.game_turns
    set status = 'voting',
        proof_photo_url = case
          when v_turn.prompt_kind = 'dare' then p_proof_path
          else proof_photo_url
        end
    where id = p_turn_id;
  end if;
end;
$$;

revoke all on function public.complete_truth_or_dare_turn(uuid, text, text) from public, anon;

grant execute on function public.complete_truth_or_dare_turn(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- RPC: vote on a turn awaiting a verdict
-- Upserts the caller's vote (changing your mind is allowed until
-- the vote resolves), then resolves the turn the moment the
-- outcome is mathematically decided.
-- ------------------------------------------------------------

create or replace function public.vote_truth_or_dare_turn(p_turn_id uuid, p_vote boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn     public.game_turns%rowtype;
  v_session  public.game_sessions%rowtype;
  v_eligible integer;
  v_yes      integer;
  v_no       integer;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_turn
  from public.game_turns
  where id = p_turn_id
  for update;

  if not found then
    raise exception 'turn not found';
  end if;

  if v_turn.status <> 'voting' then
    raise exception 'turn is not open for voting';
  end if;

  if v_turn.player_id = auth.uid() then
    raise exception 'you cannot vote on your own turn';
  end if;

  select * into v_session
  from public.game_sessions
  where id = v_turn.session_id
  for update;

  if v_session.status <> 'active' then
    raise exception 'game is not active';
  end if;

  if not exists (
    select 1 from public.game_players
    where session_id = v_session.id and user_id = auth.uid()
  ) then
    raise exception 'only players in the game can vote';
  end if;

  insert into public.game_turn_votes (turn_id, voter_id, vote)
  values (p_turn_id, auth.uid(), p_vote)
  on conflict (turn_id, voter_id)
  do update set vote = excluded.vote, created_at = now();

  select count(*) into v_eligible
  from public.game_players
  where session_id = v_session.id and user_id <> v_turn.player_id;

  select count(*) filter (where vote),
         count(*) filter (where not vote)
    into v_yes, v_no
  from public.game_turn_votes
  where turn_id = p_turn_id;

  if v_yes * 2 > v_eligible then
    -- Majority says it counts.
    update public.game_turns
    set status = 'completed',
        completed_at = now()
    where id = p_turn_id;

    perform public.advance_truth_or_dare_turn(v_session.id, v_turn.turn_number);
  elsif (v_eligible - v_no) * 2 <= v_eligible then
    -- Even if everyone left votes yes it's at best a tie: voted out.
    update public.game_turns
    set status = 'failed',
        completed_at = now()
    where id = p_turn_id;

    perform public.advance_truth_or_dare_turn(v_session.id, v_turn.turn_number);
  end if;
end;
$$;

revoke all on function public.vote_truth_or_dare_turn(uuid, boolean) from public, anon;

grant execute on function public.vote_truth_or_dare_turn(uuid, boolean) to authenticated;

-- ------------------------------------------------------------
-- RPC: end the game — also discard a turn stuck mid-vote
-- ------------------------------------------------------------

create or replace function public.end_truth_or_dare(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.game_sessions%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select * into v_session
  from public.game_sessions
  where id = p_session_id
  for update;

  if not found then
    raise exception 'game not found';
  end if;

  if v_session.status = 'ended' then
    return;
  end if;

  if v_session.started_by <> auth.uid() and not public.is_meetup_host(v_session.meetup_id) then
    raise exception 'only the starter or meetup host can end the game';
  end if;

  -- Discard the open turn so it does not linger on the scoreboard.
  delete from public.game_turns
  where session_id = p_session_id
    and status in ('pending', 'prompted', 'voting');

  update public.game_sessions
  set status = 'ended',
      ended_at = now()
  where id = p_session_id;
end;
$$;

revoke all on function public.end_truth_or_dare(uuid) from public, anon;

grant execute on function public.end_truth_or_dare(uuid) to authenticated;

-- ------------------------------------------------------------
-- Realtime
-- ------------------------------------------------------------

do $$
begin
  alter publication supabase_realtime add table public.game_turn_votes;
exception
  when duplicate_object then null;
end $$
;
