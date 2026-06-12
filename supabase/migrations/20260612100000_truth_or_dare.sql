-- ============================================================
-- Truth or Dare group game
--
-- A game session lives inside a meetup. Any participant can start
-- one; other participants join the lobby, and the starter begins
-- the game. Turn order is randomized server-side and loops until
-- the game ends.
--
-- All state transitions (start / join / begin / coin flip / turn
-- completion / end) go through SECURITY DEFINER RPCs so the coin
-- flip and prompt draw are server-authoritative — every player
-- sees the same outcome via Realtime. Clients have read-only
-- access to the tables.
-- ============================================================

-- ------------------------------------------------------------
-- Prompt deck
-- ------------------------------------------------------------

create table if not exists public.game_prompts (
  id    uuid primary key default gen_random_uuid(),
  kind  text not null check (kind in ('truth', 'dare')),
  tier  text not null check (tier in ('normal', 'spicy')),
  text  text not null,
  unique (kind, tier, text)
);

alter table public.game_prompts enable row level security;

drop policy if exists "authenticated read prompts" on public.game_prompts;
create policy "authenticated read prompts"
  on public.game_prompts for select
  to authenticated
  using (true);

insert into public.game_prompts (kind, tier, text) values
  -- Truths — normal
  ('truth', 'normal', 'What is the most embarrassing thing in your camera roll right now?'),
  ('truth', 'normal', 'Who at this table would you call first if you got arrested?'),
  ('truth', 'normal', 'What is the longest you have gone without showering?'),
  ('truth', 'normal', 'What is a food opinion you have that would get you cancelled?'),
  ('truth', 'normal', 'What is the most childish thing you still do?'),
  ('truth', 'normal', 'Have you ever pretended not to see someone here in public? Who?'),
  ('truth', 'normal', 'What is the worst gift you have ever received, and who gave it?'),
  ('truth', 'normal', 'What is your most-used emoji and what does that say about you?'),
  ('truth', 'normal', 'What is the dumbest way you have ever injured yourself?'),
  ('truth', 'normal', 'Which person at this table has the best style, and which needs help?'),
  ('truth', 'normal', 'What show do you pretend you have never watched?'),
  ('truth', 'normal', 'What is the last lie you told, and who did you tell it to?'),
  ('truth', 'normal', 'If you had to trade phones with someone here for a day, who scares you the least?'),
  ('truth', 'normal', 'What is your guilty-pleasure song? Sing the chorus.'),
  ('truth', 'normal', 'What is one thing your parents still do not know about you?'),
  -- Truths — spicy
  ('truth', 'spicy', 'Who in this squad would you date if you absolutely had to pick one?'),
  ('truth', 'spicy', 'What is the most embarrassing reason you have ever been ghosted?'),
  ('truth', 'spicy', 'Read the last DM you sent out loud.'),
  ('truth', 'spicy', 'What is the wildest thing you have done to get someone''s attention?'),
  ('truth', 'spicy', 'Have you ever had a crush on a friend''s partner? Spill.'),
  ('truth', 'spicy', 'What is the biggest red flag you have ever ignored?'),
  ('truth', 'spicy', 'What is the most chaotic thing you have done after midnight?'),
  ('truth', 'spicy', 'Who was your worst kiss ever, and what made it so bad?'),
  ('truth', 'spicy', 'What is something you have done that you would judge someone else for?'),
  ('truth', 'spicy', 'Show the group your most recent search history. Explain the weirdest one.'),
  ('truth', 'spicy', 'Have you ever snooped through a partner''s phone? What did you find?'),
  ('truth', 'spicy', 'What is the pettiest reason you have ever ended things with someone?'),
  ('truth', 'spicy', 'Rank everyone at this table by who texts back the worst.'),
  ('truth', 'spicy', 'What is a secret you have kept from everyone in this group until now?'),
  ('truth', 'spicy', 'What is the most embarrassing thing you have cried about this year?'),
  -- Dares — normal (photo-provable)
  ('dare', 'normal', 'Take a selfie making the ugliest face you can manage.'),
  ('dare', 'normal', 'Let the person to your left restyle your hair, then pose for a photo.'),
  ('dare', 'normal', 'Do your best superhero landing and hold it for a photo.'),
  ('dare', 'normal', 'Take a dramatic soap-opera-style portrait staring into the distance.'),
  ('dare', 'normal', 'Balance something from the table on your head and get photographed.'),
  ('dare', 'normal', 'Strike your best runway pose wherever you are right now.'),
  ('dare', 'normal', 'Take a photo of yourself doing a plank, right now, wherever you are.'),
  ('dare', 'normal', 'Recreate a famous album cover using only what is within reach.'),
  ('dare', 'normal', 'Make the face you make in your worst ID photo. Capture it.'),
  ('dare', 'normal', 'Pose like a statue in a museum until someone takes your photo.'),
  ('dare', 'normal', 'Wear your jacket or shirt backwards and pose like it is fashion.'),
  ('dare', 'normal', 'Do your best impression of the person to your right, on camera.'),
  ('dare', 'normal', 'Take a mirror selfie with the most influencer caption energy possible.'),
  ('dare', 'normal', 'Stack as many objects as you can on one hand and photograph it.'),
  ('dare', 'normal', 'Photo of you mid-jump. It must be airborne or it does not count.'),
  -- Dares — spicy (photo-provable)
  ('dare', 'spicy', 'Let the group write a text and send it to anyone they pick. Screenshot it, then photo your reaction.'),
  ('dare', 'spicy', 'Fake-call your most recent crush''s contact and pose with the call screen.'),
  ('dare', 'spicy', 'Let someone here draw on your face with whatever is available. Selfie required.'),
  ('dare', 'spicy', 'Serenade a stranger or staff member. Photo of the performance.'),
  ('dare', 'spicy', 'Post the group''s choice of selfie to your story right now. Photo of it posted.'),
  ('dare', 'spicy', 'Swap an item of clothing with the person across from you. Pose together.'),
  ('dare', 'spicy', 'Do 20 push-ups right now, wherever you are. Mid-push-up photo.'),
  ('dare', 'spicy', 'Ask a stranger for a selfie together and show us the result.'),
  ('dare', 'spicy', 'Eat a bite of the group''s most cursed food combination. Photo mid-bite.'),
  ('dare', 'spicy', 'Let the group pick your profile photo for the next 24 hours. Photo of it set.'),
  ('dare', 'spicy', 'Do your most dramatic slow-motion hair flip for the camera.'),
  ('dare', 'spicy', 'Hold an ice cube in your hand until it melts. Photo of the aftermath.'),
  ('dare', 'spicy', 'Let someone here go through your camera roll and pick one photo for the game feed.'),
  ('dare', 'spicy', 'Speak in an accent chosen by the group until your next turn. Photo of you mid-performance.'),
  ('dare', 'spicy', 'Dance with no music for 30 seconds. Most unflattering action shot wins.')
on conflict (kind, tier, text) do nothing;

-- ------------------------------------------------------------
-- Game sessions
-- ------------------------------------------------------------

create table if not exists public.game_sessions (
  id                  uuid        primary key default gen_random_uuid(),
  meetup_id           uuid        not null references public.meetups(id) on delete cascade,
  started_by          uuid        not null references public.profiles(id) on delete cascade,
  tier                text        not null check (tier in ('normal', 'spicy')),
  status              text        not null default 'lobby' check (status in ('lobby', 'active', 'ended')),
  turn_order          uuid[]      not null default '{}',
  current_turn_index  integer     not null default 0,
  created_at          timestamptz not null default now(),
  ended_at            timestamptz
);

create index if not exists game_sessions_meetup_idx on public.game_sessions(meetup_id);

-- One live (lobby or active) game per meetup at a time.
create unique index if not exists game_sessions_one_live_per_meetup
  on public.game_sessions(meetup_id)
  where status in ('lobby', 'active');

alter table public.game_sessions enable row level security;

drop policy if exists "participants read game sessions" on public.game_sessions;
create policy "participants read game sessions"
  on public.game_sessions for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

-- ------------------------------------------------------------
-- Game players
-- ------------------------------------------------------------

create table if not exists public.game_players (
  session_id  uuid        not null references public.game_sessions(id) on delete cascade,
  user_id     uuid        not null references public.profiles(id) on delete cascade,
  joined_at   timestamptz not null default now(),
  primary key (session_id, user_id)
);

create index if not exists game_players_user_idx on public.game_players(user_id);

alter table public.game_players enable row level security;

drop policy if exists "participants read game players" on public.game_players;
create policy "participants read game players"
  on public.game_players for select
  to authenticated
  using (
    exists (
      select 1
      from public.game_sessions gs
      where gs.id = session_id
        and (
          public.is_meetup_host(gs.meetup_id)
          or public.is_meetup_participant(gs.meetup_id, auth.uid())
        )
    )
  );

-- ------------------------------------------------------------
-- Game turns
-- ------------------------------------------------------------
-- status lifecycle:
--   pending   → the player has not flipped the coin yet
--   prompted  → coin landed; prompt drawn; waiting for completion/pass
--   completed → truth answered or dare proven with a photo
--   passed    → player chickened out (tracked on the scoreboard)

create table if not exists public.game_turns (
  id               uuid        primary key default gen_random_uuid(),
  session_id       uuid        not null references public.game_sessions(id) on delete cascade,
  turn_number      integer     not null,
  player_id        uuid        not null references public.profiles(id) on delete cascade,
  status           text        not null default 'pending' check (status in ('pending', 'prompted', 'completed', 'passed')),
  coin_result      text        check (coin_result in ('heads', 'tails')),
  prompt_kind      text        check (prompt_kind in ('truth', 'dare')),
  prompt_text      text,
  proof_photo_url  text,
  created_at       timestamptz not null default now(),
  completed_at     timestamptz,
  unique (session_id, turn_number)
);

create index if not exists game_turns_session_idx on public.game_turns(session_id);

alter table public.game_turns enable row level security;

drop policy if exists "participants read game turns" on public.game_turns;
create policy "participants read game turns"
  on public.game_turns for select
  to authenticated
  using (
    exists (
      select 1
      from public.game_sessions gs
      where gs.id = session_id
        and (
          public.is_meetup_host(gs.meetup_id)
          or public.is_meetup_participant(gs.meetup_id, auth.uid())
        )
    )
  );

-- ------------------------------------------------------------
-- RPC: start a game session (creates the lobby, auto-joins starter)
-- ------------------------------------------------------------

create or replace function public.start_truth_or_dare(p_meetup_id uuid, p_tier text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_tier not in ('normal', 'spicy') then
    raise exception 'invalid tier';
  end if;

  if not (public.is_meetup_host(p_meetup_id) or public.is_meetup_participant(p_meetup_id, auth.uid())) then
    raise exception 'not a meetup participant';
  end if;

  if exists (
    select 1 from public.game_sessions
    where meetup_id = p_meetup_id and status in ('lobby', 'active')
  ) then
    raise exception 'a game is already running in this meetup';
  end if;

  insert into public.game_sessions (meetup_id, started_by, tier)
  values (p_meetup_id, auth.uid(), p_tier)
  returning id into v_session_id;

  insert into public.game_players (session_id, user_id)
  values (v_session_id, auth.uid());

  return v_session_id;
end;
$$;
revoke all on function public.start_truth_or_dare(uuid, text) from public, anon;
grant execute on function public.start_truth_or_dare(uuid, text) to authenticated;

-- ------------------------------------------------------------
-- RPC: join a session (lobby, or mid-game — appended to turn order)
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

  if not (public.is_meetup_host(v_session.meetup_id)
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
-- RPC: begin the game (starter only) — randomizes turn order,
-- creates the first turn
-- ------------------------------------------------------------

create or replace function public.begin_truth_or_dare(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_session public.game_sessions%rowtype;
  v_order   uuid[];
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

  if v_session.started_by <> auth.uid() then
    raise exception 'only the player who started the game can begin it';
  end if;

  if v_session.status <> 'lobby' then
    raise exception 'game already started';
  end if;

  select array_agg(user_id order by random()) into v_order
  from public.game_players
  where session_id = p_session_id;

  if v_order is null or array_length(v_order, 1) < 2 then
    raise exception 'need at least 2 players';
  end if;

  update public.game_sessions
  set status = 'active',
      turn_order = v_order,
      current_turn_index = 0
  where id = p_session_id;

  insert into public.game_turns (session_id, turn_number, player_id)
  values (p_session_id, 1, v_order[1]);
end;
$$;
revoke all on function public.begin_truth_or_dare(uuid) from public, anon;
grant execute on function public.begin_truth_or_dare(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: flip the coin (current player only)
-- Server decides heads/tails and draws the prompt, so the result
-- is identical on every device.
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
  set status = 'prompted',
      coin_result = v_result,
      prompt_kind = v_kind,
      prompt_text = v_prompt
  where id = p_turn_id;

  return query select v_result, v_kind, v_prompt;
end;
$$;
revoke all on function public.flip_truth_or_dare_coin(uuid) from public, anon;
grant execute on function public.flip_truth_or_dare_coin(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: complete or pass the current turn, then advance the loop
-- A dare can only be completed with a proof photo path.
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
  v_turn        public.game_turns%rowtype;
  v_session     public.game_sessions%rowtype;
  v_next_index  integer;
  v_next_player uuid;
  v_count       integer;
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

  update public.game_turns
  set status = case p_action when 'done' then 'completed' else 'passed' end,
      proof_photo_url = case
        when p_action = 'done' and v_turn.prompt_kind = 'dare' then p_proof_path
        else proof_photo_url
      end,
      completed_at = now()
  where id = p_turn_id;

  -- Advance the loop to the next player.
  v_count := array_length(v_session.turn_order, 1);
  v_next_index := v_session.current_turn_index + 1;
  v_next_player := v_session.turn_order[(v_next_index % v_count) + 1];

  update public.game_sessions
  set current_turn_index = v_next_index
  where id = v_session.id;

  insert into public.game_turns (session_id, turn_number, player_id)
  values (v_session.id, v_turn.turn_number + 1, v_next_player);
end;
$$;
revoke all on function public.complete_truth_or_dare_turn(uuid, text, text) from public, anon;
grant execute on function public.complete_truth_or_dare_turn(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- RPC: end the game (starter or meetup host)
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
    and status in ('pending', 'prompted');

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
  alter publication supabase_realtime add table public.game_sessions;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.game_players;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.game_turns;
exception
  when duplicate_object then null;
end $$;
