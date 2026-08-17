-- ============================================================
-- Meetup comments
-- Participants can post lightweight text comments on a meetup, and iOS
-- subscribes to this table through Supabase Realtime.
-- ============================================================

create table if not exists public.meetup_comments (
  id             uuid        primary key default gen_random_uuid(),
  meetup_id      uuid        not null references public.meetups(id) on delete cascade,
  author_user_id uuid        not null references public.profiles(id) on delete cascade,
  body           text        not null,
  created_at     timestamptz not null default now(),
  constraint meetup_comments_body_not_blank check (length(btrim(body)) > 0),
  constraint meetup_comments_body_length check (char_length(body) <= 1000)
);

create index if not exists meetup_comments_meetup_created_idx
  on public.meetup_comments(meetup_id, created_at);

create index if not exists meetup_comments_author_idx
  on public.meetup_comments(author_user_id);

alter table public.meetup_comments enable row level security;

drop policy if exists "participants read meetup comments" on public.meetup_comments;
create policy "participants read meetup comments"
  on public.meetup_comments for select
  to authenticated
  using (
    public.is_meetup_host(meetup_id)
    or public.is_meetup_participant(meetup_id, auth.uid())
  );

drop policy if exists "participants post meetup comments" on public.meetup_comments;
create policy "participants post meetup comments"
  on public.meetup_comments for insert
  to authenticated
  with check (
    author_user_id = auth.uid()
    and (
      public.is_meetup_host(meetup_id)
      or public.is_meetup_participant(meetup_id, auth.uid())
    )
  );

drop policy if exists "authors delete meetup comments" on public.meetup_comments;
create policy "authors delete meetup comments"
  on public.meetup_comments for delete
  to authenticated
  using (author_user_id = auth.uid());

create or replace function public.list_meetup_comments(p_meetup_id uuid)
returns table (
  id uuid,
  meetup_id uuid,
  author_user_id uuid,
  body text,
  created_at timestamptz,
  author_display_name text,
  author_avatar_url text
)
language sql
security definer
set search_path = public
as $$
  select
    mc.id,
    mc.meetup_id,
    mc.author_user_id,
    mc.body,
    mc.created_at,
    p.display_name as author_display_name,
    p.avatar_url as author_avatar_url
  from public.meetup_comments mc
  join public.profiles p on p.id = mc.author_user_id
  where mc.meetup_id = p_meetup_id
    and (
      public.is_meetup_host(p_meetup_id)
      or public.is_meetup_participant(p_meetup_id, auth.uid())
    )
  order by mc.created_at asc, mc.id asc;
$$;

revoke all on function public.list_meetup_comments(uuid) from public, anon;
grant execute on function public.list_meetup_comments(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.meetup_comments;
exception
  when duplicate_object then null;
end $$;
