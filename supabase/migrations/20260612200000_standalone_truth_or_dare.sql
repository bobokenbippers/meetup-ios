-- ============================================================
-- Standalone Truth or Dare
--
-- Decouples game sessions from meetups. A session can now exist
-- without a meetup (meetup_id IS NULL); friends join standalone
-- sessions with a short shareable invite code instead of meetup
-- membership. Meetup-embedded sessions keep working unchanged.
-- ============================================================

-- ------------------------------------------------------------
-- Schema: nullable meetup_id + unique invite code
-- ------------------------------------------------------------

alter table public.game_sessions
  alter column meetup_id drop not null;

alter table public.game_sessions
  add column if not exists invite_code text unique;

create index if not exists game_sessions_invite_code_idx
  on public.game_sessions(invite_code);

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

-- 6-char uppercase alphanumeric code, skipping ambiguous chars
-- (0/O, 1/I) so it survives being read out loud across a table.
create or replace function public.generate_game_invite_code()
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  v_alphabet constant text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code     text;
begin
  loop
    v_code := '';
    for i in 1..6 loop
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    end loop;
    exit when not exists (
      select 1 from public.game_sessions where invite_code = v_code
    );
  end loop;
  return v_code;
end;
$$;
revoke all on function public.generate_game_invite_code() from public, anon, authenticated;

-- Player membership check usable inside RLS policies on the game
-- tables without recursing into game_players' own policy.
create or replace function public.is_game_player(p_session_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_players
    where session_id = p_session_id
      and user_id = p_user_id
  );
$$;
revoke all on function public.is_game_player(uuid, uuid) from public, anon;
grant execute on function public.is_game_player(uuid, uuid) to authenticated;

-- Backfill codes for existing sessions so every session is joinable
-- by code from now on.
update public.game_sessions
set invite_code = public.generate_game_invite_code()
where invite_code is null;

alter table public.game_sessions
  alter column invite_code set not null;

-- ------------------------------------------------------------
-- RLS: players always see their own sessions; meetup host /
-- participants keep access to meetup-embedded sessions.
-- Writes still happen only inside SECURITY DEFINER RPCs.
-- ------------------------------------------------------------

drop policy if exists "participants read game sessions" on public.game_sessions;
create policy "players and participants read game sessions"
  on public.game_sessions for select
  to authenticated
  using (
    public.is_game_player(id, auth.uid())
    or (
      meetup_id is not null
      and (
        public.is_meetup_host(meetup_id)
        or public.is_meetup_participant(meetup_id, auth.uid())
      )
    )
  );

drop policy if exists "participants read game players" on public.game_players;
create policy "players and participants read game players"
  on public.game_players for select
  to authenticated
  using (
    public.is_game_player(session_id, auth.uid())
    or exists (
      select 1
      from public.game_sessions gs
      where gs.id = session_id
        and gs.meetup_id is not null
        and (
          public.is_meetup_host(gs.meetup_id)
          or public.is_meetup_participant(gs.meetup_id, auth.uid())
        )
    )
  );

drop policy if exists "participants read game turns" on public.game_turns;
create policy "players and participants read game turns"
  on public.game_turns for select
  to authenticated
  using (
    public.is_game_player(session_id, auth.uid())
    or exists (
      select 1
      from public.game_sessions gs
      where gs.id = session_id
        and gs.meetup_id is not null
        and (
          public.is_meetup_host(gs.meetup_id)
          or public.is_meetup_participant(gs.meetup_id, auth.uid())
        )
    )
  );

-- game_turn_votes exists on the hosted project (migration
-- 20260612110000, applied outside this repo). Extend its read
-- policy the same way, guarded so a fresh local stack without that
-- table still applies cleanly.
do $$
begin
  if to_regclass('public.game_turn_votes') is not null then
    drop policy if exists "participants read turn votes" on public.game_turn_votes;
    create policy "players and participants read turn votes"
      on public.game_turn_votes for select
      to authenticated
      using (
        exists (
          select 1
          from public.game_turns gt
          join public.game_sessions gs on gs.id = gt.session_id
          where gt.id = turn_id
            and (
              public.is_game_player(gs.id, auth.uid())
              or (
                gs.meetup_id is not null
                and (
                  public.is_meetup_host(gs.meetup_id)
                  or public.is_meetup_participant(gs.meetup_id, auth.uid())
                )
              )
            )
        )
      );
  end if;
end $$;

-- ------------------------------------------------------------
-- RPC: start a session — meetup is now optional. Any authenticated
-- user can start a standalone game; meetup games still require
-- membership. Returns the session id and its invite code.
-- ------------------------------------------------------------

drop function if exists public.start_truth_or_dare(uuid, text);

create or replace function public.start_truth_or_dare(p_tier text, p_meetup_id uuid default null)
returns table (session_id uuid, invite_code text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
  v_code       text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_tier not in ('normal', 'spicy') then
    raise exception 'invalid tier';
  end if;

  if p_meetup_id is not null then
    if not (public.is_meetup_host(p_meetup_id) or public.is_meetup_participant(p_meetup_id, auth.uid())) then
      raise exception 'not a meetup participant';
    end if;

    if exists (
      select 1 from public.game_sessions
      where meetup_id = p_meetup_id and status in ('lobby', 'active')
    ) then
      raise exception 'a game is already running in this meetup';
    end if;
  end if;

  v_code := public.generate_game_invite_code();

  insert into public.game_sessions (meetup_id, started_by, tier, invite_code)
  values (p_meetup_id, auth.uid(), p_tier, v_code)
  returning id into v_session_id;

  insert into public.game_players (session_id, user_id)
  values (v_session_id, auth.uid());

  return query select v_session_id, v_code;
end;
$$;
revoke all on function public.start_truth_or_dare(text, uuid) from public, anon;
grant execute on function public.start_truth_or_dare(text, uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: join by session id. Meetup sessions still require meetup
-- membership; standalone sessions are joinable by anyone holding
-- the session id (only reachable via the invite code or an
-- existing player's device).
-- ------------------------------------------------------------

create or replace function public.join_truth_or_dare(p_session_id uuid)
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
    raise exception 'game has ended';
  end if;

  if v_session.meetup_id is not null
     and not (public.is_meetup_host(v_session.meetup_id)
              or public.is_meetup_participant(v_session.meetup_id, auth.uid())) then
    raise exception 'not a meetup participant';
  end if;

  insert into public.game_players (session_id, user_id)
  values (p_session_id, auth.uid())
  on conflict (session_id, user_id) do nothing;

  -- Joining a live game: slot in at the end of the loop.
  if v_session.status = 'active' and not (auth.uid() = any (v_session.turn_order)) then
    update public.game_sessions
    set turn_order = turn_order || auth.uid()
    where id = p_session_id;
  end if;
end;
$$;
revoke all on function public.join_truth_or_dare(uuid) from public, anon;
grant execute on function public.join_truth_or_dare(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: join by invite code. Looks up the live session for the
-- code and adds the caller as a player. Returns the session id
-- so the client can open the game directly.
-- ------------------------------------------------------------

create or replace function public.join_truth_or_dare_by_code(p_code text)
returns uuid
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
  where invite_code = upper(trim(p_code))
  for update;

  if not found then
    raise exception 'no game found for that code';
  end if;

  if v_session.status = 'ended' then
    raise exception 'that game has already ended';
  end if;

  insert into public.game_players (session_id, user_id)
  values (v_session.id, auth.uid())
  on conflict (session_id, user_id) do nothing;

  if v_session.status = 'active' and not (auth.uid() = any (v_session.turn_order)) then
    update public.game_sessions
    set turn_order = turn_order || auth.uid()
    where id = v_session.id;
  end if;

  return v_session.id;
end;
$$;
revoke all on function public.join_truth_or_dare_by_code(text) from public, anon;
grant execute on function public.join_truth_or_dare_by_code(text) to authenticated;

-- ------------------------------------------------------------
-- RPC: end the game — handle sessions without a meetup (only the
-- starter can end those; meetup sessions also allow the host).
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

  if v_session.started_by <> auth.uid()
     and not (v_session.meetup_id is not null and public.is_meetup_host(v_session.meetup_id)) then
    raise exception 'only the starter or meetup host can end the game';
  end if;

  -- Discard the open turn (including one stuck mid-vote) so it does
  -- not linger on the scoreboard.
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
