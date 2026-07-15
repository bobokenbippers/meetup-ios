-- Privacy audit log for sensitive location-sharing lifecycle events.

create table if not exists public.privacy_audit_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  meetup_id uuid references public.meetups(id) on delete set null,
  event_type text not null check (
    event_type in (
      'location_sharing_started',
      'location_sharing_stopped',
      'location_cleared',
      'meetup_completed'
    )
  ),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists privacy_audit_logs_user_created_idx
  on public.privacy_audit_logs (user_id, created_at desc);

create index if not exists privacy_audit_logs_meetup_idx
  on public.privacy_audit_logs (meetup_id);

alter table public.privacy_audit_logs enable row level security;

drop policy if exists "users read own privacy audit logs" on public.privacy_audit_logs;
create policy "users read own privacy audit logs"
  on public.privacy_audit_logs for select
  using (auth.uid() = user_id);

drop policy if exists "users insert own privacy audit logs" on public.privacy_audit_logs;
create policy "users insert own privacy audit logs"
  on public.privacy_audit_logs for insert
  with check (
    auth.uid() = user_id
    and (actor_id is null or actor_id = auth.uid())
  );

create or replace function public.log_meetup_completion_privacy_event()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed' and old.status is distinct from new.status then
    insert into public.privacy_audit_logs (user_id, actor_id, meetup_id, event_type, metadata)
    select
      mp.user_id,
      coalesce(auth.uid(), new.host_id),
      new.id,
      'meetup_completed',
      jsonb_build_object('destination_name', new.destination_name)
    from public.meetup_participants mp
    where mp.meetup_id = new.id;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_log_meetup_completion_privacy_event on public.meetups;
create trigger trg_log_meetup_completion_privacy_event
  after update of status on public.meetups
  for each row execute function public.log_meetup_completion_privacy_event();
