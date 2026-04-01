-- Friends live location for map friend mode (mutual followers).
alter table public.users
  add column if not exists live_latitude double precision,
  add column if not exists live_longitude double precision,
  add column if not exists live_location_updated_at timestamptz;

create index if not exists idx_users_live_location_updated_at
  on public.users (live_location_updated_at desc);

create index if not exists idx_users_live_location_coords
  on public.users (live_latitude, live_longitude);
