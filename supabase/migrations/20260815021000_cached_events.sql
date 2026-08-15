-- Cached third-party event suggestions.
--
-- Ingestion runs server-side with privileged credentials. The iOS app reads
-- normalized, soon-upcoming events near the user's current location.

create table if not exists public.cached_events (
  id              uuid primary key default gen_random_uuid(),
  source_name     text not null,
  source_event_id text not null,
  title           text not null check (char_length(trim(title)) > 0),
  venue_name      text,
  address         text,
  lat             double precision not null check (lat between -90 and 90),
  lng             double precision not null check (lng between -180 and 180),
  starts_at       timestamptz,
  source_url      text not null,
  image_url       text,
  category        text,
  last_seen_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (source_name, source_event_id)
);

create index if not exists cached_events_starts_at_idx
  on public.cached_events (starts_at);

create index if not exists cached_events_last_seen_idx
  on public.cached_events (last_seen_at desc);

create index if not exists cached_events_category_idx
  on public.cached_events (category);

create index if not exists cached_events_lat_lng_idx
  on public.cached_events (lat, lng);

alter table public.cached_events enable row level security;

drop policy if exists "authenticated users read cached events" on public.cached_events;
create policy "authenticated users read cached events"
  on public.cached_events for select
  to authenticated
  using (true);

drop policy if exists "service role manages cached events" on public.cached_events;
create policy "service role manages cached events"
  on public.cached_events for all
  to service_role
  using (true)
  with check (true);

create or replace function public.touch_cached_events_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_touch_cached_events_updated_at on public.cached_events;
create trigger trg_touch_cached_events_updated_at
  before update on public.cached_events
  for each row execute function public.touch_cached_events_updated_at();

create or replace function public.search_cached_events(
  p_lat double precision,
  p_lng double precision,
  p_radius_miles integer default 5,
  p_category text default null,
  p_limit integer default 20
)
returns table (
  id uuid,
  source_name text,
  source_event_id text,
  title text,
  venue_name text,
  address text,
  lat double precision,
  lng double precision,
  starts_at timestamptz,
  source_url text,
  image_url text,
  category text,
  distance_miles double precision
)
language sql
stable
security definer
set search_path = public
as $$
  with ranked as (
    select
      ce.id,
      ce.source_name,
      ce.source_event_id,
      ce.title,
      ce.venue_name,
      ce.address,
      ce.lat,
      ce.lng,
      ce.starts_at,
      ce.source_url,
      ce.image_url,
      ce.category,
      (
        3958.7613 * acos(
          least(1.0, greatest(-1.0,
            cos(radians(p_lat)) * cos(radians(ce.lat)) *
            cos(radians(ce.lng) - radians(p_lng)) +
            sin(radians(p_lat)) * sin(radians(ce.lat))
          ))
        )
      ) as distance_miles
    from public.cached_events ce
    where ce.last_seen_at >= now() - interval '2 days'
      and (ce.starts_at is null or ce.starts_at >= now() - interval '6 hours')
      and (p_category is null or ce.category is null or ce.category ilike p_category)
  )
  select *
  from ranked
  where distance_miles <= greatest(1, p_radius_miles)
  order by
    case when starts_at is null then 1 else 0 end,
    starts_at asc nulls last,
    distance_miles asc
  limit least(greatest(p_limit, 1), 50);
$$;

revoke all on function public.search_cached_events(double precision, double precision, integer, text, integer)
  from public, anon;
grant execute on function public.search_cached_events(double precision, double precision, integer, text, integer)
  to authenticated;
