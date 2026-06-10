-- Notify all live participants when a host cancels a meetup.
-- Reuses the public.call_push_function helper + Vault service-role key wired up in
-- 20260609_push_triggers.sql. Fires only on a real cancellation (status -> 'cancelled'),
-- not on auto-expiry (status -> 'ended').

create or replace function public.notify_meetup_cancelled()
returns trigger language plpgsql security definer as $$
begin
  if new.status = 'cancelled' and old.status is distinct from 'cancelled' then
    perform public.call_push_function(
      'push-meetup-cancelled',
      jsonb_build_object('meetupId', new.id)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_notify_meetup_cancelled on public.meetups;
create trigger trg_notify_meetup_cancelled
  after update on public.meetups
  for each row execute function public.notify_meetup_cancelled();
