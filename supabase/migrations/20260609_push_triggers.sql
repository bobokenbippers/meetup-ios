-- Wire the push edge functions to database events.
-- These were designed to be "Triggered by Postgres" but no triggers existed,
-- so meetup-invite / meetup-status / friend-request pushes never fired.
--
-- Auth: internal calls to edge functions need a service-role bearer token to pass
-- the functions' JWT verification. The original design used
-- current_setting('app.service_role_key'), but the Supabase `postgres` role can't
-- ALTER DATABASE ... SET that GUC. Instead the key lives in Supabase Vault under
-- the name 'service_role_key' (stored out-of-band so it never lands in git):
--   select vault.create_secret('<service_role key>', 'service_role_key');

create extension if not exists pg_net;
create extension if not exists pg_cron;

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
      'Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' limit 1)
    ),
    body := payload
  );
end;
$$;
revoke all on function public.call_push_function(text, jsonb) from public, anon, authenticated;

-- 1) New invite → notify the invitee
create or replace function public.notify_meetup_invite()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'invited' then
    perform public.call_push_function(
      'push-meetup-invite',
      jsonb_build_object('meetupId', new.meetup_id, 'userId', new.user_id)
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
      jsonb_build_object('meetupId', new.meetup_id, 'userId', new.user_id, 'newStatus', new.status)
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

-- Re-point the existing maintenance crons at the Vault-based key. They were
-- scheduled with current_setting('app.service_role_key') which was always NULL,
-- so expire-meetups and push-leave-now have never actually run.
select cron.schedule(
  'expire-meetups',
  '*/5 * * * *',
  $cron$
  select net.http_post(
    url := 'https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/expire-meetups',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' limit 1)
    ),
    body := '{}'::jsonb
  );
  $cron$
);

select cron.schedule(
  'leave-now-push',
  '*/5 * * * *',
  $cron$
  select net.http_post(
    url := 'https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/push-leave-now',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' ||
        (select decrypted_secret from vault.decrypted_secrets where name = 'service_role_key' limit 1)
    ),
    body := '{}'::jsonb
  );
  $cron$
);
