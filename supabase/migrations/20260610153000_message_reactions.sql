-- ============================================================
-- Direct Message Reactions
-- Emoji reactions on 1:1 direct messages between accepted friends.
-- ============================================================

create table if not exists public.message_reactions (
  id          uuid        primary key default gen_random_uuid(),
  message_id  uuid        not null references public.messages(id) on delete cascade,
  user_id     uuid        not null references public.profiles(id) on delete cascade,
  emoji       text        not null,
  created_at  timestamptz not null default now(),
  constraint message_reactions_emoji_length check (char_length(emoji) between 1 and 16),
  unique (message_id, user_id, emoji)
);

create index if not exists message_reactions_message_idx
  on public.message_reactions(message_id);

create index if not exists message_reactions_user_idx
  on public.message_reactions(user_id);

alter table public.message_reactions enable row level security;

drop policy if exists "members read message reactions" on public.message_reactions;
create policy "members read message reactions"
  on public.message_reactions for select
  using (
    exists (
      select 1
      from public.messages m
      where m.id = message_id
        and public.can_message_conversation(m.conversation_id)
    )
  );

drop policy if exists "members react as themselves" on public.message_reactions;
create policy "members react as themselves"
  on public.message_reactions for insert
  with check (
    user_id = auth.uid()
    and emoji in ('❤️', '😂', '😮', '😢', '🔥', '👍')
    and exists (
      select 1
      from public.messages m
      where m.id = message_id
        and public.can_message_conversation(m.conversation_id)
    )
  );

drop policy if exists "members delete their own reactions" on public.message_reactions;
create policy "members delete their own reactions"
  on public.message_reactions for delete
  using (user_id = auth.uid());

create or replace function public.list_message_reactions(p_conversation_id uuid)
returns table (
  message_id      uuid,
  emoji           text,
  reaction_count  integer,
  reacted_by_me   boolean
)
language sql
security definer
set search_path = public
as $$
  select
    mr.message_id,
    mr.emoji,
    count(*)::integer as reaction_count,
    bool_or(mr.user_id = auth.uid()) as reacted_by_me
  from public.message_reactions mr
  join public.messages m on m.id = mr.message_id
  where m.conversation_id = p_conversation_id
    and public.can_message_conversation(p_conversation_id)
  group by mr.message_id, mr.emoji
  order by max(mr.created_at) asc;
$$;
revoke all on function public.list_message_reactions(uuid) from public, anon;
grant execute on function public.list_message_reactions(uuid) to authenticated;

create or replace function public.toggle_message_reaction(p_message_id uuid, p_emoji text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  conv_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  if p_emoji not in ('❤️', '😂', '😮', '😢', '🔥', '👍') then
    raise exception 'unsupported reaction';
  end if;

  select conversation_id into conv_id
  from public.messages
  where id = p_message_id;

  if conv_id is null or not public.can_message_conversation(conv_id) then
    raise exception 'not allowed';
  end if;

  if exists (
    select 1
    from public.message_reactions
    where message_id = p_message_id
      and user_id = auth.uid()
      and emoji = p_emoji
  ) then
    delete from public.message_reactions
    where message_id = p_message_id
      and user_id = auth.uid()
      and emoji = p_emoji;
  else
    insert into public.message_reactions (message_id, user_id, emoji)
    values (p_message_id, auth.uid(), p_emoji);
  end if;
end;
$$;
revoke all on function public.toggle_message_reaction(uuid, text) from public, anon;
grant execute on function public.toggle_message_reaction(uuid, text) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.message_reactions;
exception
  when duplicate_object then null;
end $$;
