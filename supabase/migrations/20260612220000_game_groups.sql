-- ============================================================
-- Game Groups
--
-- Persistent named groups of friends for playing Truth or Dare
-- together. The owner creates a group, adds accepted friends as
-- members, and starting a game from the group stamps the session
-- with the group id and pushes an invite (with the join code) to
-- every other member.
-- ============================================================

-- ------------------------------------------------------------
-- Schema
-- ------------------------------------------------------------

-- owner_id / user_id reference public.profiles (1:1 with
-- auth.users in this app) like the other game tables, so
-- PostgREST can embed display_name / avatar_url directly.
create table public.game_groups (
  id         uuid        primary key default gen_random_uuid(),
  name       text        not null check (char_length(trim(name)) between 1 and 60),
  owner_id   uuid        not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create index game_groups_owner_idx on public.game_groups(owner_id);

alter table public.game_groups enable row level security;

create table public.game_group_members (
  group_id  uuid        not null references public.game_groups(id) on delete cascade,
  user_id   uuid        not null references public.profiles(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);

create index game_group_members_user_idx on public.game_group_members(user_id);

alter table public.game_group_members enable row level security;

-- Sessions started from a group carry the group id; the group
-- outlives its sessions, so deleting a group keeps the games.
alter table public.game_sessions
  add column if not exists group_id uuid references public.game_groups(id) on delete set null;

create index if not exists game_sessions_group_idx on public.game_sessions(group_id);

-- ------------------------------------------------------------
-- Helpers (SECURITY DEFINER so RLS policies on the group tables
-- can use them without recursing into their own policies)
-- ------------------------------------------------------------

create or replace function public.is_game_group_owner(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_groups
    where id = p_group_id and owner_id = p_user_id
  );
$$;
revoke all on function public.is_game_group_owner(uuid, uuid) from public, anon;
grant execute on function public.is_game_group_owner(uuid, uuid) to authenticated;

create or replace function public.is_game_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.game_group_members
    where group_id = p_group_id and user_id = p_user_id
  );
$$;
revoke all on function public.is_game_group_member(uuid, uuid) from public, anon;
grant execute on function public.is_game_group_member(uuid, uuid) to authenticated;

-- ------------------------------------------------------------
-- RLS
-- ------------------------------------------------------------

create policy "owner and members read game groups"
  on public.game_groups for select
  to authenticated
  using (owner_id = auth.uid() or public.is_game_group_member(id, auth.uid()));

create policy "users create game groups they own"
  on public.game_groups for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "owner updates game groups"
  on public.game_groups for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "owner deletes game groups"
  on public.game_groups for delete
  to authenticated
  using (owner_id = auth.uid());

-- Members of a group can see the full roster (the group detail
-- screen shows every member to every member, not just the owner).
create policy "owner and members read group members"
  on public.game_group_members for select
  to authenticated
  using (
    public.is_game_group_owner(group_id, auth.uid())
    or public.is_game_group_member(group_id, auth.uid())
  );

-- Membership writes go through the SECURITY DEFINER RPCs below
-- (which enforce the friend gate); the direct policies mirror the
-- same authority for defense in depth.
create policy "owner adds group members"
  on public.game_group_members for insert
  to authenticated
  with check (public.is_game_group_owner(group_id, auth.uid()));

create policy "owner removes members or member leaves"
  on public.game_group_members for delete
  to authenticated
  using (
    public.is_game_group_owner(group_id, auth.uid())
    or user_id = auth.uid()
  );

-- ------------------------------------------------------------
-- RPC: create a group; the creator becomes owner + first member
-- ------------------------------------------------------------

create or replace function public.create_game_group(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_group_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_name is null or char_length(trim(p_name)) = 0 then
    raise exception 'group name is required';
  end if;

  insert into public.game_groups (name, owner_id)
  values (trim(p_name), auth.uid())
  returning id into v_group_id;

  insert into public.game_group_members (group_id, user_id)
  values (v_group_id, auth.uid());

  return v_group_id;
end;
$$;
revoke all on function public.create_game_group(text) from public, anon;
grant execute on function public.create_game_group(text) to authenticated;

-- ------------------------------------------------------------
-- RPC: add a member — owner only, and only accepted friends of
-- the owner can be added.
-- ------------------------------------------------------------

create or replace function public.add_game_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if not public.is_game_group_owner(p_group_id, auth.uid()) then
    raise exception 'only the group owner can add members';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'owner is already a member';
  end if;

  if not public.is_accepted_friend(auth.uid(), p_user_id) then
    raise exception 'you can only add accepted friends to a group';
  end if;

  insert into public.game_group_members (group_id, user_id)
  values (p_group_id, p_user_id)
  on conflict (group_id, user_id) do nothing;
end;
$$;
revoke all on function public.add_game_group_member(uuid, uuid) from public, anon;
grant execute on function public.add_game_group_member(uuid, uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: remove a member — owner only (owner removes themselves by
-- deleting the group instead).
-- ------------------------------------------------------------

create or replace function public.remove_game_group_member(p_group_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if not public.is_game_group_owner(p_group_id, auth.uid()) then
    raise exception 'only the group owner can remove members';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'the owner cannot be removed; delete the group instead';
  end if;

  delete from public.game_group_members
  where group_id = p_group_id and user_id = p_user_id;
end;
$$;
revoke all on function public.remove_game_group_member(uuid, uuid) from public, anon;
grant execute on function public.remove_game_group_member(uuid, uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: leave a group — any member except the owner.
-- ------------------------------------------------------------

create or replace function public.leave_game_group(p_group_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if public.is_game_group_owner(p_group_id, auth.uid()) then
    raise exception 'the owner cannot leave; delete the group instead';
  end if;

  if not public.is_game_group_member(p_group_id, auth.uid()) then
    raise exception 'not a member of this group';
  end if;

  delete from public.game_group_members
  where group_id = p_group_id and user_id = auth.uid();
end;
$$;
revoke all on function public.leave_game_group(uuid) from public, anon;
grant execute on function public.leave_game_group(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: start_truth_or_dare grows an optional p_group_id. A group
-- game must be started by a group member; the session is stamped
-- with the group and every other member gets a push with the
-- invite code (via the push-game-group-start edge function).
-- ------------------------------------------------------------

drop function if exists public.start_truth_or_dare(text, uuid);

create or replace function public.start_truth_or_dare(
  p_tier text,
  p_meetup_id uuid default null,
  p_group_id uuid default null
)
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

  if p_meetup_id is not null and p_group_id is not null then
    raise exception 'a game belongs to a meetup or a group, not both';
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

  if p_group_id is not null
     and not public.is_game_group_member(p_group_id, auth.uid()) then
    raise exception 'not a member of this group';
  end if;

  v_code := public.generate_game_invite_code();

  insert into public.game_sessions (meetup_id, group_id, started_by, tier, invite_code)
  values (p_meetup_id, p_group_id, auth.uid(), p_tier, v_code)
  returning id into v_session_id;

  insert into public.game_players (session_id, user_id)
  values (v_session_id, auth.uid());

  -- Push "X started a game" to the other group members. pg_net
  -- queues the HTTP call; the guard keeps a missing vault secret
  -- or push outage from failing the game start itself.
  if p_group_id is not null then
    begin
      perform public.call_push_function(
        'push-game-group-start',
        jsonb_build_object(
          'sessionId', v_session_id,
          'groupId',   p_group_id,
          'starterId', auth.uid()
        )
      );
    exception when others then
      raise warning 'game group push failed: %', sqlerrm;
    end;
  end if;

  return query select v_session_id, v_code;
end;
$$;
revoke all on function public.start_truth_or_dare(text, uuid, uuid) from public, anon;
grant execute on function public.start_truth_or_dare(text, uuid, uuid) to authenticated;
