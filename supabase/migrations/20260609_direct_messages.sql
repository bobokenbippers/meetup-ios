-- ============================================================
-- Direct Messages (1:1 DM between accepted friends)
-- Run in Supabase SQL editor or via `supabase db push`.
-- ============================================================

-- ------------------------------------------------------------
-- conversations: one canonical row per accepted friend-pair.
-- user_a_id < user_b_id (uuid ordering) mirrors the friendships table.
-- ------------------------------------------------------------
create table if not exists public.conversations (
  id               uuid        primary key default gen_random_uuid(),
  user_a_id        uuid        not null references public.profiles(id) on delete cascade,
  user_b_id        uuid        not null references public.profiles(id) on delete cascade,
  last_message_at  timestamptz,
  last_read_a      timestamptz,   -- last time user_a read this thread
  last_read_b      timestamptz,   -- last time user_b read this thread
  created_at       timestamptz not null default now(),
  constraint conversations_user_a_lt_user_b check (user_a_id < user_b_id),
  unique (user_a_id, user_b_id)
);

create index if not exists conversations_user_a_idx on public.conversations(user_a_id);
create index if not exists conversations_user_b_idx on public.conversations(user_b_id);

-- ------------------------------------------------------------
-- messages: text and/or image. Users can delete their own messages.
-- ------------------------------------------------------------
create table if not exists public.messages (
  id               uuid        primary key default gen_random_uuid(),
  conversation_id  uuid        not null references public.conversations(id) on delete cascade,
  sender_id        uuid        not null references public.profiles(id) on delete cascade,
  body             text,
  image_path       text,       -- storage path inside the message-photos bucket (NOT a signed URL)
  created_at       timestamptz not null default now(),
  constraint messages_has_content check (body is not null or image_path is not null)
);

create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);

-- ------------------------------------------------------------
-- Helpers (SECURITY DEFINER so policies can see across rows).
-- ------------------------------------------------------------

-- Am I (auth.uid()) a participant in this conversation?
create or replace function public.is_conversation_member(p_conversation_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
  );
$$;

-- Am I a participant AND still accepted friends with the other party?
-- Gates reads/writes to the conversation behind an accepted friendship,
-- mirroring is_accepted_friend() used by the meetup-invite gate.
create or replace function public.can_message_conversation(p_conversation_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.conversations c
    where c.id = p_conversation_id
      and (c.user_a_id = auth.uid() or c.user_b_id = auth.uid())
      and public.is_accepted_friend(c.user_a_id, c.user_b_id)
  );
$$;

-- ------------------------------------------------------------
-- RLS: conversations
-- ------------------------------------------------------------
alter table public.conversations enable row level security;

drop policy if exists "members see their conversations" on public.conversations;
create policy "members see their conversations"
  on public.conversations for select
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

drop policy if exists "members create conversations between accepted friends" on public.conversations;
create policy "members create conversations between accepted friends"
  on public.conversations for insert
  with check (
    (auth.uid() = user_a_id or auth.uid() = user_b_id)
    and user_a_id < user_b_id
    and public.is_accepted_friend(user_a_id, user_b_id)
  );

-- Needed for last_read / last_message_at bookkeeping.
drop policy if exists "members update their conversations" on public.conversations;
create policy "members update their conversations"
  on public.conversations for update
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

drop policy if exists "members delete their conversations" on public.conversations;
create policy "members delete their conversations"
  on public.conversations for delete
  using (auth.uid() = user_a_id or auth.uid() = user_b_id);

-- ------------------------------------------------------------
-- RLS: messages
-- ------------------------------------------------------------
alter table public.messages enable row level security;

-- Reads gated to accepted friends.
drop policy if exists "members read messages in their conversations" on public.messages;
create policy "members read messages in their conversations"
  on public.messages for select
  using (public.can_message_conversation(conversation_id));

-- Sending gated to accepted friends; sender must be self.
drop policy if exists "members send messages as themselves" on public.messages;
create policy "members send messages as themselves"
  on public.messages for insert
  with check (
    sender_id = auth.uid()
    and public.can_message_conversation(conversation_id)
  );

drop policy if exists "senders delete their own messages" on public.messages;
create policy "senders delete their own messages"
  on public.messages for delete
  using (sender_id = auth.uid());

-- ------------------------------------------------------------
-- RPC: get_or_create_conversation
-- Returns the conversation id for the accepted-friend pair, creating the
-- canonical row on first use. SECURITY DEFINER handles the user_a<user_b
-- ordering and the accepted-friend check in one round trip.
-- ------------------------------------------------------------
create or replace function public.get_or_create_conversation(p_other_user_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  me      uuid := auth.uid();
  a       uuid;
  b       uuid;
  conv_id uuid;
begin
  if me is null then
    raise exception 'not authenticated';
  end if;
  if not public.is_accepted_friend(me, p_other_user_id) then
    raise exception 'not accepted friends';
  end if;

  if me < p_other_user_id then
    a := me; b := p_other_user_id;
  else
    a := p_other_user_id; b := me;
  end if;

  select id into conv_id from public.conversations
   where user_a_id = a and user_b_id = b;

  if conv_id is null then
    insert into public.conversations (user_a_id, user_b_id)
    values (a, b)
    returning id into conv_id;
  end if;

  return conv_id;
end;
$$;
revoke all on function public.get_or_create_conversation(uuid) from public, anon;
grant execute on function public.get_or_create_conversation(uuid) to authenticated;

-- ------------------------------------------------------------
-- RPC: list_conversation_summaries
-- Inbox feed in a single round trip: one row per conversation with the
-- last message preview and the caller's unread count.
-- ------------------------------------------------------------
create or replace function public.list_conversation_summaries()
returns table (
  conversation_id uuid,
  other_user_id   uuid,
  last_message_at timestamptz,
  last_body       text,
  last_image_path text,
  last_sender_id  uuid,
  unread_count    bigint
)
language sql
security definer
set search_path = public
as $$
  with my_convs as (
    select
      c.id,
      c.last_message_at,
      case when c.user_a_id = auth.uid() then c.user_b_id else c.user_a_id end as other_id,
      case when c.user_a_id = auth.uid() then c.last_read_a else c.last_read_b end as my_last_read
    from public.conversations c
    where c.user_a_id = auth.uid() or c.user_b_id = auth.uid()
  )
  select
    mc.id,
    mc.other_id,
    mc.last_message_at,
    lm.body,
    lm.image_path,
    lm.sender_id,
    coalesce((
      select count(*)
      from public.messages m
      where m.conversation_id = mc.id
        and m.sender_id <> auth.uid()
        and m.created_at > coalesce(mc.my_last_read, 'epoch'::timestamptz)
    ), 0) as unread_count
  from my_convs mc
  left join lateral (
    select body, image_path, sender_id
    from public.messages m
    where m.conversation_id = mc.id
    order by m.created_at desc
    limit 1
  ) lm on true
  order by mc.last_message_at desc nulls last;
$$;
revoke all on function public.list_conversation_summaries() from public, anon;
grant execute on function public.list_conversation_summaries() to authenticated;

-- ------------------------------------------------------------
-- RPC: mark_conversation_read
-- ------------------------------------------------------------
create or replace function public.mark_conversation_read(p_conversation_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.conversations
     set last_read_a = case when user_a_id = auth.uid() then now() else last_read_a end,
         last_read_b = case when user_b_id = auth.uid() then now() else last_read_b end
   where id = p_conversation_id
     and (user_a_id = auth.uid() or user_b_id = auth.uid());
end;
$$;
revoke all on function public.mark_conversation_read(uuid) from public, anon;
grant execute on function public.mark_conversation_read(uuid) to authenticated;

-- ------------------------------------------------------------
-- Trigger: on new message → bump last_message_at + fire push.
-- Uses the call_push_function vault helper from 20260609_push_triggers.sql.
-- ------------------------------------------------------------
create or replace function public.on_new_message()
returns trigger
language plpgsql
security definer
as $$
begin
  update public.conversations
     set last_message_at = new.created_at
   where id = new.conversation_id;

  perform public.call_push_function(
    'push-new-message',
    jsonb_build_object('messageId', new.id)
  );
  return new;
end;
$$;

drop trigger if exists trg_on_new_message on public.messages;
create trigger trg_on_new_message
  after insert on public.messages
  for each row execute function public.on_new_message();

-- Keep inbox ordering accurate when the most recent message is deleted.
create or replace function public.on_delete_message()
returns trigger
language plpgsql
security definer
as $$
begin
  update public.conversations
     set last_message_at = (
       select max(created_at)
       from public.messages
       where conversation_id = old.conversation_id
     )
   where id = old.conversation_id;
  return old;
end;
$$;

drop trigger if exists trg_on_delete_message on public.messages;
create trigger trg_on_delete_message
  after delete on public.messages
  for each row execute function public.on_delete_message();

-- ------------------------------------------------------------
-- Realtime: publish messages + conversations so the iOS realtimeV2
-- channels receive postgres_changes events.
-- ------------------------------------------------------------
do $$
begin
  alter publication supabase_realtime add table public.messages;
exception
  when duplicate_object then null;
end $$;

do $$
begin
  alter publication supabase_realtime add table public.conversations;
exception
  when duplicate_object then null;
end $$;

-- ============================================================
-- Storage bucket: message-photos
-- ============================================================
insert into storage.buckets (id, name, public)
values ('message-photos', 'message-photos', false)
on conflict (id) do nothing;
--
-- Files are stored at path: <conversation_id>/<uuid>.jpg
-- Signed URLs expire in 3600 seconds (1 hour).
--
-- Storage RLS policies on storage.objects (Dashboard → Storage → Policies),
-- scoped to the message-photos bucket. A participant of the conversation
-- (folder name == conversation_id) may read / write / delete. We reuse the
-- is_conversation_member() helper, casting the first path segment to uuid.

drop policy if exists "dm members read message photos" on storage.objects;
create policy "dm members read message photos"
  on storage.objects for select
  using (
    bucket_id = 'message-photos'
    and public.is_conversation_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "dm members upload message photos" on storage.objects;
create policy "dm members upload message photos"
  on storage.objects for insert
  with check (
    bucket_id = 'message-photos'
    and public.is_conversation_member((storage.foldername(name))[1]::uuid)
  );

drop policy if exists "dm members delete message photos" on storage.objects;
create policy "dm members delete message photos"
  on storage.objects for delete
  using (
    bucket_id = 'message-photos'
    and public.is_conversation_member((storage.foldername(name))[1]::uuid)
  );
