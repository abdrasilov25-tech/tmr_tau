-- LIVE Battle: безопасность и идемпотентный finalize.

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
  if p_host_a is distinct from auth.uid() then
    raise exception 'must_be_challenger';
  end if;
  if p_host_b = p_host_a then
    raise exception 'same_opponent';
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
  v_host_a uuid;
  v_host_b uuid;
  v_points int := 1;
  v_last_like_at timestamptz;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'auth_required';
  end if;

  select end_time, is_active, host_a, host_b
  into v_end_time, v_is_active, v_host_a, v_host_b
  from public.live_battles
  where id = p_battle_id
  for update;
  if not found then
    raise exception 'battle_not_found';
  end if;
  if not v_is_active or v_end_time <= v_now then
    raise exception 'battle_finished';
  end if;
  if p_target_host is distinct from v_host_a and p_target_host is distinct from v_host_b then
    raise exception 'invalid_target_host';
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
  v_host_a uuid;
  v_host_b uuid;
  v_price int;
  v_balance int;
  v_points int;
  v_last_gift_at timestamptz;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'auth_required';
  end if;

  select end_time, is_active, host_a, host_b
  into v_end_time, v_is_active, v_host_a, v_host_b
  from public.live_battles
  where id = p_battle_id
  for update;
  if not found then
    raise exception 'battle_not_found';
  end if;
  if not v_is_active or v_end_time <= v_now then
    raise exception 'battle_finished';
  end if;
  if p_target_host is distinct from v_host_a and p_target_host is distinct from v_host_b then
    raise exception 'invalid_target_host';
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

  if not v_b.is_active then
    return jsonb_build_object(
      'battle_id', v_b.id,
      'winner_id', v_b.winner_id,
      'score_a', v_b.score_a,
      'score_b', v_b.score_b,
      'mvp_sender_id', v_b.mvp_sender_id,
      'top3_donators', v_b.top3_donators
    );
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
