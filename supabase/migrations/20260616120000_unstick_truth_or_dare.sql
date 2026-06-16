-- ============================================================
-- Un-stick Truth or Dare games.
--
-- Two failure modes were trapping players in dead games:
--   1. Only the session starter (or meetup host) could end a game.
--      A standalone game started by someone else, then soft-locked,
--      was un-killable for every other player — no UI button and the
--      RPC rejected them.
--   2. Nothing ever cleaned up abandoned sessions: one-player lobbies
--      that never started, and active games whose turn stalled, sat
--      "live" forever in everyone's games list.
--
-- Fix: let ANY player end the game, and add a janitor cron that ends
-- stale lobbies and abandoned active games on its own.
-- ============================================================

-- ------------------------------------------------------------
-- RPC: end the game — now any player in the session can end it
-- (plus the meetup host for meetup-embedded games). Keeps the
-- open-turn cleanup so a stuck turn never lingers on the scoreboard.
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

  -- Any player in the session can put a dead game out of its misery.
  -- Meetup-embedded games also allow the meetup host (who may not have
  -- joined the game) to end it.
  if not exists (
        select 1 from public.game_players gp
        where gp.session_id = p_session_id
          and gp.user_id = auth.uid()
     )
     and not (v_session.meetup_id is not null and public.is_meetup_host(v_session.meetup_id)) then
    raise exception 'only a player or the meetup host can end the game';
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

-- ------------------------------------------------------------
-- Janitor: end abandoned sessions so they stop showing as live.
--   * lobbies older than 6h that never reached 2 players
--   * active games with no turn activity in the last 12h
-- Runs as the function owner (no service-role key needed), purely
-- over local tables.
-- ------------------------------------------------------------
create or replace function public.expire_stale_game_sessions()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  -- A session is stale when it's an abandoned lobby (older than 6h and
  -- never reached 2 players) or an active game whose last turn (or, if
  -- no turns, its creation) was over 12h ago.
  with stale as (
    select s.id
    from public.game_sessions s
    where (
            s.status = 'lobby'
            and s.created_at < now() - interval '6 hours'
            and (select count(*) from public.game_players gp where gp.session_id = s.id) < 2
          )
       or (
            s.status = 'active'
            and coalesce(
                  (select max(t.created_at) from public.game_turns t where t.session_id = s.id),
                  s.created_at
                ) < now() - interval '12 hours'
          )
  )
  -- Clear any open turns so the scoreboard stays clean.
  delete from public.game_turns t
  using stale
  where t.session_id = stale.id
    and t.status in ('pending', 'prompted', 'voting');

  with stale as (
    select s.id
    from public.game_sessions s
    where (
            s.status = 'lobby'
            and s.created_at < now() - interval '6 hours'
            and (select count(*) from public.game_players gp where gp.session_id = s.id) < 2
          )
       or (
            s.status = 'active'
            and coalesce(
                  (select max(t.created_at) from public.game_turns t where t.session_id = s.id),
                  s.created_at
                ) < now() - interval '12 hours'
          )
  )
  update public.game_sessions s
  set status = 'ended',
      ended_at = now()
  from stale
  where s.id = stale.id;

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke all on function public.expire_stale_game_sessions() from public, anon, authenticated;

-- Schedule the janitor every 30 minutes (idempotent re-run).
create extension if not exists pg_cron;

select cron.unschedule('expire-stale-games')
where exists (select 1 from cron.job where jobname = 'expire-stale-games');

select cron.schedule(
  'expire-stale-games',
  '*/30 * * * *',
  $$ select public.expire_stale_game_sessions(); $$
);
