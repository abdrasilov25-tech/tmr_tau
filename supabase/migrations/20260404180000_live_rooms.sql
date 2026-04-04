-- Комнаты прямого эфира (Agora channel id = id::text).

create table if not exists public.live_rooms (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.users(id) on delete cascade,
  title text not null default '',
  is_live boolean not null default true,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists idx_live_rooms_live_created
  on public.live_rooms (is_live, created_at desc);

alter table public.live_rooms enable row level security;

drop policy if exists live_rooms_select_auth on public.live_rooms;
create policy live_rooms_select_auth on public.live_rooms
  for select
  to authenticated
  using (is_live = true or host_id = (select auth.uid()));

drop policy if exists live_rooms_insert_own on public.live_rooms;
create policy live_rooms_insert_own on public.live_rooms
  for insert
  to authenticated
  with check (host_id = (select auth.uid()));

drop policy if exists live_rooms_update_own on public.live_rooms;
create policy live_rooms_update_own on public.live_rooms
  for update
  to authenticated
  using (host_id = (select auth.uid()))
  with check (host_id = (select auth.uid()));

alter table public.live_rooms replica identity full;

-- Включите Realtime для таблицы live_rooms: Dashboard → Database → Replication,
-- или: alter publication supabase_realtime add table public.live_rooms;
