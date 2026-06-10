-- device_tokens: per-device APNs token registry for push notification targeting
create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete cascade not null,
  token text not null,
  platform text not null default 'ios',
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique(user_id, token)
);
alter table public.device_tokens enable row level security;
create policy "Users manage own tokens" on public.device_tokens
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Schedule leave-now push every 5 minutes via pg_cron + pg_net
create extension if not exists pg_cron;

select cron.schedule(
  'leave-now-push',
  '*/5 * * * *',
  $$
  select net.http_post(
    url := 'https://boyrqhbdkqzffvfokpri.supabase.co/functions/v1/push-leave-now',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    ),
    body := '{}'::jsonb
  );
  $$
);
