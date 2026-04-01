-- LIVE battles + Qarmet gifts economy.

create table if not exists public.gift_catalog (
  id text primary key,
  name text not null,
  price int not null check (price > 0),
  animation text not null default 'default'
);

insert into public.gift_catalog (id, name, price, animation)
values
  ('gift_1', 'Gift 1', 1, 'spark'),
  ('gift_5', 'Gift 5', 5, 'spark'),
  ('gift_10', 'Gift 10', 10, 'spark'),
  ('gift_30', 'Gift 30', 30, 'spark'),
  ('gift_50', 'Gift 50', 50, 'spark'),
  ('gift_80', 'Gift 80', 80, 'spark'),
  ('gift_150', 'Gift 150', 150, 'spark'),
  ('gift_300', 'Gift 300', 300, 'spark'),
  ('gift_500', 'Gift 500', 500, 'spark'),
  ('gift_1000', 'Gift 1000', 1000, 'spark')
on conflict (id) do update
set name = excluded.name,
    price = excluded.price,
    animation = excluded.animation;

create table if not exists public.live_battles (
  id uuid primary key default gen_random_uuid(),
  host_a uuid not null references public.users(id) on delete cascade,
  host_b uuid not null references public.users(id) on delete cascade,
  score_a int not null default 0 check (score_a >= 0),
  score_b int not null default 0 check (score_b >= 0),
  end_time timestamptz not null,
  is_active boolean not null default true,
  winner_id uuid references public.users(id) on delete set null,
  mvp_sender_id uuid references public.users(id) on delete set null,
  top3_donators jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.live_battle_events (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.live_battles(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  target_host uuid not null references public.users(id) on delete cascade,
  event_type text not null check (event_type in ('like', 'gift')),
  gift_id text references public.gift_catalog(id) on delete set null,
  gift_price int not null default 0 check (gift_price >= 0),
  points_awarded int not null default 0 check (points_awarded >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_live_battle_events_battle_created
  on public.live_battle_events (battle_id, created_at desc);
create index if not exists idx_live_battle_events_sender_created
  on public.live_battle_events (sender_id, created_at desc);

create table if not exists public.live_battle_results (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null unique references public.live_battles(id) on delete cascade,
  host_a uuid not null references public.users(id) on delete cascade,
  host_b uuid not null references public.users(id) on delete cascade,
  winner_id uuid references public.users(id) on delete set null,
  score_a int not null default 0,
  score_b int not null default 0,
  mvp_sender_id uuid references public.users(id) on delete set null,
  top3_donators jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.gift_catalog enable row level security;
alter table public.live_battles enable row level security;
alter table public.live_battle_events enable row level security;
alter table public.live_battle_results enable row level security;

drop policy if exists gift_catalog_select_auth on public.gift_catalog;
create policy gift_catalog_select_auth on public.gift_catalog
for select to authenticated
using (true);

drop policy if exists live_battles_select_auth on public.live_battles;
create policy live_battles_select_auth on public.live_battles
for select to authenticated
using (true);

drop policy if exists live_battle_events_select_auth on public.live_battle_events;
create policy live_battle_events_select_auth on public.live_battle_events
for select to authenticated
using (true);

drop policy if exists live_battle_results_select_auth on public.live_battle_results;
create policy live_battle_results_select_auth on public.live_battle_results
for select to authenticated
using (true);

create or replace function public.start_live_battle(
  p_host_a uuid,
  p_host_b uuid,
  p_duration_seconds int default 300
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_battle_id uuid;
begin
  if auth.uid() is null then
    raise exception 'auth_required';
  end if;
  if p_duration_seconds < 60 then
    raise exception 'duration_too_short';
  end if;
  insert into public.live_battles (host_a, host_b, end_time)
  values (p_host_a, p_host_b, now() + make_interval(secs => p_duration_seconds))
  returning id into v_battle_id;
  return v_battle_id;
end;
$$;

create or replace function public.send_live_battle_like(
  p_battle_id uuid,
  p_target_host uuid
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_now timestamptz := now();
  v_end_time timestamptz;
  v_is_active boolean;
  v_points int := 1;
  v_last_like_at timestamptz;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'auth_required';
  end if;

  select end_time, is_active into v_end_time, v_is_active
  from public.live_battles
  where id = p_battle_id
  for update;
  if not found then
    raise exception 'battle_not_found';
  end if;
  if not v_is_active or v_end_time <= v_now then
    raise exception 'battle_finished';
  end if;
  if v_end_time - v_now <= interval '30 seconds' then
    v_points := 2;
  end if;

  select max(created_at) into v_last_like_at
  from public.live_battle_events
  where battle_id = p_battle_id
    and sender_id = v_user_id
    and event_type = 'like';
  if v_last_like_at is not null and (v_now - v_last_like_at) < interval '300 milliseconds' then
    raise exception 'like_rate_limited';
  end if;

  insert into public.live_battle_events (
    battle_id, sender_id, target_host, event_type, points_awarded
  ) values (
    p_battle_id, v_user_id, p_target_host, 'like', v_points
  );

  update public.live_battles
  set score_a = case when host_a = p_target_host then score_a + v_points else score_a end,
      score_b = case when host_b = p_target_host then score_b + v_points else score_b end,
      updated_at = v_now
  where id = p_battle_id;

  return v_points;
end;
$$;

create or replace function public.send_live_battle_gift(
  p_battle_id uuid,
  p_gift_id text,
  p_target_host uuid
) returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_now timestamptz := now();
  v_end_time timestamptz;
  v_is_active boolean;
  v_price int;
  v_balance int;
  v_points int;
  v_last_gift_at timestamptz;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'auth_required';
  end if;

  select end_time, is_active into v_end_time, v_is_active
  from public.live_battles
  where id = p_battle_id
  for update;
  if not found then
    raise exception 'battle_not_found';
  end if;
  if not v_is_active or v_end_time <= v_now then
    raise exception 'battle_finished';
  end if;

  select max(created_at) into v_last_gift_at
  from public.live_battle_events
  where battle_id = p_battle_id
    and sender_id = v_user_id
    and event_type = 'gift';
  if v_last_gift_at is not null and (v_now - v_last_gift_at) < interval '700 milliseconds' then
    raise exception 'gift_rate_limited';
  end if;

  select price into v_price
  from public.gift_catalog
  where id = p_gift_id;
  if v_price is null then
    raise exception 'gift_not_found';
  end if;

  select qarmet_balance into v_balance
  from public.users
  where id = v_user_id
  for update;
  if v_balance is null then
    raise exception 'user_not_found';
  end if;
  if v_balance < v_price then
    raise exception 'insufficient_qarmet';
  end if;

  update public.users
  set qarmet_balance = qarmet_balance - v_price
  where id = v_user_id;

  v_points := v_price;
  if v_end_time - v_now <= interval '30 seconds' then
    v_points := v_points * 2;
  end if;

  insert into public.live_battle_events (
    battle_id, sender_id, target_host, event_type, gift_id, gift_price, points_awarded
  ) values (
    p_battle_id, v_user_id, p_target_host, 'gift', p_gift_id, v_price, v_points
  );

  update public.live_battles
  set score_a = case when host_a = p_target_host then score_a + v_points else score_a end,
      score_b = case when host_b = p_target_host then score_b + v_points else score_b end,
      updated_at = v_now
  where id = p_battle_id;

  return v_points;
end;
$$;

create or replace function public.finalize_live_battle(
  p_battle_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_b public.live_battles%rowtype;
  v_winner uuid;
  v_mvp uuid;
  v_top3 jsonb := '[]'::jsonb;
begin
  if auth.uid() is null then
    raise exception 'auth_required';
  end if;

  select * into v_b
  from public.live_battles
  where id = p_battle_id
  for update;
  if not found then
    raise exception 'battle_not_found';
  end if;

  if v_b.score_a > v_b.score_b then
    v_winner := v_b.host_a;
  elsif v_b.score_b > v_b.score_a then
    v_winner := v_b.host_b;
  else
    v_winner := null;
  end if;

  with donor as (
    select sender_id, sum(gift_price)::int as amount
    from public.live_battle_events
    where battle_id = p_battle_id
      and event_type = 'gift'
    group by sender_id
    order by amount desc
    limit 3
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object('user_id', sender_id, 'amount', amount)
      order by amount desc
    ),
    '[]'::jsonb
  )
  into v_top3
  from donor;

  select sender_id into v_mvp
  from (
    select sender_id, sum(gift_price)::int as amount
    from public.live_battle_events
    where battle_id = p_battle_id
      and event_type = 'gift'
    group by sender_id
    order by amount desc
    limit 1
  ) t;

  update public.live_battles
  set is_active = false,
      winner_id = v_winner,
      mvp_sender_id = v_mvp,
      top3_donators = v_top3,
      updated_at = now()
  where id = p_battle_id;

  insert into public.live_battle_results (
    battle_id, host_a, host_b, winner_id, score_a, score_b, mvp_sender_id, top3_donators
  )
  values (
    v_b.id, v_b.host_a, v_b.host_b, v_winner, v_b.score_a, v_b.score_b, v_mvp, v_top3
  )
  on conflict (battle_id) do update
  set winner_id = excluded.winner_id,
      score_a = excluded.score_a,
      score_b = excluded.score_b,
      mvp_sender_id = excluded.mvp_sender_id,
      top3_donators = excluded.top3_donators;

  return jsonb_build_object(
    'battle_id', v_b.id,
    'winner_id', v_winner,
    'score_a', v_b.score_a,
    'score_b', v_b.score_b,
    'mvp_sender_id', v_mvp,
    'top3_donators', v_top3
  );
end;
$$;

revoke all on function public.start_live_battle(uuid, uuid, int) from public;
grant execute on function public.start_live_battle(uuid, uuid, int) to authenticated;
revoke all on function public.send_live_battle_like(uuid, uuid) from public;
grant execute on function public.send_live_battle_like(uuid, uuid) to authenticated;
revoke all on function public.send_live_battle_gift(uuid, text, uuid) from public;
grant execute on function public.send_live_battle_gift(uuid, text, uuid) to authenticated;
revoke all on function public.finalize_live_battle(uuid) from public;
grant execute on function public.finalize_live_battle(uuid) to authenticated;
