-- ============================================================
-- Custom dare assignment
--
-- After the coin flips to dare (status = 'prompted'), any other
-- game player can set a custom dare text before the doer acts.
-- The doer sees a "waiting" state until dare_locked = true.
--
-- dare_locked = false  → assigning phase; other players choose
--                         the dare; doer waits
-- dare_locked = true   → dare confirmed; doer acts
--
-- Truths skip this phase: they stay dare_locked = true always
-- (the column is only meaningful when prompt_kind = 'dare').
-- ============================================================

-- ------------------------------------------------------------
-- Schema: dare_locked flag
-- ------------------------------------------------------------

alter table public.game_turns
  add column if not exists dare_locked boolean not null default false;

-- Backfill: non-dare turns and already-done turns are treated as
-- locked so existing games continue to work normally.
update public.game_turns
set dare_locked = true
where prompt_kind <> 'dare'
   or status in ('completed', 'passed');

-- ------------------------------------------------------------
-- Update flip_truth_or_dare_coin to auto-lock truths
--
-- Dares start with dare_locked = false so the assigner sees the
-- UI. Truths are immediately locked (no assignment step needed).
-- ------------------------------------------------------------

create or replace function public.flip_truth_or_dare_coin(p_turn_id uuid)
returns table (coin_result text, prompt_kind text, prompt_text text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn    public.game_turns%rowtype;
  v_session public.game_sessions%rowtype;
  v_result  text;
  v_kind    text;
  v_prompt  text;
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

  if v_turn.player_id <> auth.uid() then
    raise exception 'not your turn';
  end if;

  if v_turn.status <> 'pending' then
    raise exception 'coin already flipped';
  end if;

  select * into v_session
  from public.game_sessions
  where id = v_turn.session_id;

  if v_session.status <> 'active' then
    raise exception 'game is not active';
  end if;

  v_result := case when random() < 0.5 then 'heads' else 'tails' end;
  v_kind   := case v_result when 'heads' then 'truth' else 'dare' end;

  -- Draw a prompt not yet used in this session; fall back to any
  -- prompt of the right kind/tier if the deck is exhausted.
  select gp.text into v_prompt
  from public.game_prompts gp
  where gp.kind = v_kind
    and gp.tier = v_session.tier
    and gp.text not in (
      select gt.prompt_text from public.game_turns gt
      where gt.session_id = v_turn.session_id
        and gt.prompt_text is not null
    )
  order by random()
  limit 1;

  if v_prompt is null then
    select gp.text into v_prompt
    from public.game_prompts gp
    where gp.kind = v_kind and gp.tier = v_session.tier
    order by random()
    limit 1;
  end if;

  if v_prompt is null then
    raise exception 'prompt deck is empty';
  end if;

  update public.game_turns
  set status      = 'prompted',
      coin_result = v_result,
      prompt_kind = v_kind,
      prompt_text = v_prompt,
      -- Truths are immediately locked; dares wait for an assigner.
      dare_locked = (v_kind = 'truth')
  where id = p_turn_id;

  return query select v_result, v_kind, v_prompt;
end;
$$;
revoke all on function public.flip_truth_or_dare_coin(uuid) from public, anon;
grant execute on function public.flip_truth_or_dare_coin(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: assign_dare_prompt
--
-- Called by any game player who is NOT the current turn's player.
-- Accepts the app-suggested dare as-is, or sets a custom text.
-- Once called, dare_locked becomes true and the doer can proceed.
-- A second call (from a different player racing to assign) returns
-- silently — the first assigner wins.
-- ------------------------------------------------------------

create or replace function public.assign_dare_prompt(
  p_turn_id    uuid,
  p_prompt_text text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turn public.game_turns%rowtype;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_prompt_text is null or length(trim(p_prompt_text)) = 0 then
    raise exception 'prompt text cannot be empty';
  end if;

  select * into v_turn
  from public.game_turns
  where id = p_turn_id
  for update;

  if not found then
    raise exception 'turn not found';
  end if;

  if v_turn.prompt_kind <> 'dare' then
    raise exception 'can only assign prompt for dare turns';
  end if;

  if v_turn.status <> 'prompted' then
    raise exception 'coin must be flipped before assigning dare';
  end if;

  if v_turn.player_id = auth.uid() then
    raise exception 'you cannot assign your own dare';
  end if;

  if not public.is_game_player(v_turn.session_id, auth.uid()) then
    raise exception 'not a game player';
  end if;

  -- First assigner wins; subsequent calls are no-ops.
  if v_turn.dare_locked then
    return;
  end if;

  update public.game_turns
  set prompt_text = trim(p_prompt_text),
      dare_locked = true
  where id = p_turn_id;
end;
$$;
revoke all on function public.assign_dare_prompt(uuid, text) from public, anon;
grant execute on function public.assign_dare_prompt(uuid, text) to authenticated;
