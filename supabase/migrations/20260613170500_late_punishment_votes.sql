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

create table if not exists public.meetup_late_punishment_proofs (
  id               uuid        primary key default gen_random_uuid(),
  meetup_id        uuid        not null references public.meetups(id) on delete cascade,
  uploader_user_id uuid        not null references public.profiles(id) on delete cascade,
  photo_url        text        not null,
  caption          text,
  created_at       timestamptz not null default now()
);

create index if not exists meetup_late_punishment_proofs_meetup_idx
  on public.meetup_late_punishment_proofs(meetup_id, created_at desc);

create table if not exists public.meetup_late_punishment_proof_reactions (
  proof_id   uuid        not null references public.meetup_late_punishment_proofs(id) on delete cascade,
  user_id    uuid        not null references public.profiles(id) on delete cascade,
  emoji      text        not null,
  created_at timestamptz not null default now(),
  primary key (proof_id, user_id, emoji),
  constraint meetup_late_punishment_proof_reactions_emoji_check check (
    emoji in ('❤️', '😂', '😮', '😢', '🔥', '👍')
  )
);

create index if not exists meetup_late_punishment_proof_reactions_proof_idx
  on public.meetup_late_punishment_proof_reactions(proof_id);

alter table public.meetup_late_punishment_votes enable row level security;
alter table public.meetup_late_punishment_proofs enable row level security;
alter table public.meetup_late_punishment_proof_reactions enable row level security;

drop policy if exists "participants read late punishment votes"
  on public.meetup_late_punishment_votes;

create policy "participants read late punishment votes"
  on public.meetup_late_punishment_votes for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

drop policy if exists "participants read late punishment proofs"
  on public.meetup_late_punishment_proofs;

create policy "participants read late punishment proofs"
  on public.meetup_late_punishment_proofs for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

drop policy if exists "participants insert late punishment proofs"
  on public.meetup_late_punishment_proofs;

create policy "participants insert late punishment proofs"
  on public.meetup_late_punishment_proofs for insert
  to authenticated
  with check (
    uploader_user_id = auth.uid()
    and (
      public.is_meetup_host(meetup_id)
      or public.is_meetup_participant(meetup_id, auth.uid())
    )
  );

drop policy if exists "participants read late punishment proof reactions"
  on public.meetup_late_punishment_proof_reactions;

create policy "participants read late punishment proof reactions"
  on public.meetup_late_punishment_proof_reactions for select
  to authenticated
  using (
    exists (
      select 1
      from public.meetup_late_punishment_proofs proof
      where proof.id = meetup_late_punishment_proof_reactions.proof_id
        and (
          public.is_meetup_host(proof.meetup_id)
          or public.is_meetup_participant(proof.meetup_id, auth.uid())
        )
    )
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

create or replace function public.list_late_punishment_proof_reactions(p_meetup_id uuid)
returns table (
  proof_id uuid,
  emoji text,
  reaction_count integer,
  reacted_by_me boolean
)
language sql
security definer
set search_path = public
as $$
  select
    reaction.proof_id,
    reaction.emoji,
    count(*)::integer as reaction_count,
    bool_or(reaction.user_id = auth.uid()) as reacted_by_me
  from public.meetup_late_punishment_proof_reactions reaction
  join public.meetup_late_punishment_proofs proof
    on proof.id = reaction.proof_id
  where proof.meetup_id = p_meetup_id
    and (
      public.is_meetup_host(p_meetup_id)
      or public.is_meetup_participant(p_meetup_id, auth.uid())
    )
  group by reaction.proof_id, reaction.emoji
  order by reaction_count desc, reaction.emoji asc;
$$;

revoke all on function public.list_late_punishment_proof_reactions(uuid) from public, anon;
grant execute on function public.list_late_punishment_proof_reactions(uuid) to authenticated;

create or replace function public.toggle_late_punishment_proof_reaction(p_proof_id uuid, p_emoji text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_meetup_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_emoji not in ('❤️', '😂', '😮', '😢', '🔥', '👍') then
    raise exception 'unsupported reaction';
  end if;

  select proof.meetup_id
    into v_meetup_id
  from public.meetup_late_punishment_proofs proof
  where proof.id = p_proof_id;

  if v_meetup_id is null then
    raise exception 'proof not found';
  end if;

  if not (
    public.is_meetup_host(v_meetup_id)
    or public.is_meetup_participant(v_meetup_id, auth.uid())
  ) then
    raise exception 'only meetup participants can react';
  end if;

  if exists (
    select 1
    from public.meetup_late_punishment_proof_reactions
    where proof_id = p_proof_id
      and user_id = auth.uid()
      and emoji = p_emoji
  ) then
    delete from public.meetup_late_punishment_proof_reactions
    where proof_id = p_proof_id
      and user_id = auth.uid()
      and emoji = p_emoji;
  else
    insert into public.meetup_late_punishment_proof_reactions (proof_id, user_id, emoji)
    values (p_proof_id, auth.uid(), p_emoji);
  end if;
end;
$$;

revoke all on function public.toggle_late_punishment_proof_reaction(uuid, text) from public, anon;
grant execute on function public.toggle_late_punishment_proof_reaction(uuid, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.meetup_late_punishment_votes;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.meetup_late_punishment_proofs;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.meetup_late_punishment_proof_reactions;
exception
  when duplicate_object then null;
end $$;
