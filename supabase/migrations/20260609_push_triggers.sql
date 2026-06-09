-- Wire the push edge functions to database events.
-- These were designed to be "Triggered by Postgres" but no triggers existed,
-- so meetup-invite / meetup-status / friend-request pushes never fired.
--
-- Auth: each call passes the service role key via current_setting('app.service_role_key').
-- That GUC must be set once on the database:
--   ALTER DATABASE postgres SET app.service_role_key = '<service_role key>';
-- (applied out-of-band so the key never lands in git)

create extension if not exists pg_net;

-- Helper: POST a JSON body to one of our edge functions with service-role auth
create or replace function public.call_push_function(fn text, payload jsonb)
returns void
language plpgsql
security definer
as $$
begin
  perform net.http_post(
    url := 'https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/' || fn,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    ),
    body := payload
  );
end;
$$;

-- 1) New invite → notify the invitee
create or replace function public.notify_meetup_invite()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'invited' then
    perform public.call_push_function(
      'push-meetup-invite',
      jsonb_build_object('participantId', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_meetup_invite on public.meetup_participants;
create trigger trg_notify_meetup_invite
  after insert on public.meetup_participants
  for each row execute function public.notify_meetup_invite();

-- 2) RSVP / arrival status change → notify host (+ others, handled in the function)
create or replace function public.notify_meetup_status()
returns trigger language plpgsql security definer as $$
begin
  if new.status is distinct from old.status
     and new.status in ('accepted', 'declined', 'arrived') then
    perform public.call_push_function(
      'push-meetup-status',
      jsonb_build_object('participantId', new.id, 'newStatus', new.status)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_meetup_status on public.meetup_participants;
create trigger trg_notify_meetup_status
  after update on public.meetup_participants
  for each row execute function public.notify_meetup_status();

-- 3) New friend request → notify the recipient
create or replace function public.notify_friend_request()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'pending' then
    perform public.call_push_function(
      'push-friend-request',
      jsonb_build_object('friendshipId', new.id, 'event', 'friend_request')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_request on public.friendships;
create trigger trg_notify_friend_request
  after insert on public.friendships
  for each row execute function public.notify_friend_request();

-- 4) Friend request accepted → notify the original requester
create or replace function public.notify_friend_accepted()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'accepted' and old.status is distinct from 'accepted' then
    perform public.call_push_function(
      'push-friend-request',
      jsonb_build_object('friendshipId', new.id, 'event', 'friend_accepted')
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_friend_accepted on public.friendships;
create trigger trg_notify_friend_accepted
  after update on public.friendships
  for each row execute function public.notify_friend_accepted();
