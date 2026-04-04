-- «Тап судьбы»: сессии, счёт, действия, награды. RPC с токен-бакетом (анти-чит).

create table if not exists public.tap_game_sessions (
  id uuid primary key default gen_random_uuid(),
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  is_active boolean not null default true
);

create index if not exists idx_tap_game_sessions_active_ends
  on public.tap_game_sessions (is_active, ends_at desc);

create table if not exists public.tap_game_scores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  session_id uuid not null references public.tap_game_sessions(id) on delete cascade,
  score int not null default 0,
  burst_balance numeric not null default 15,
  boost_ends_at timestamptz,
  shield_ends_at timestamptz,
  shield_floor int,
  jump_last_at timestamptz,
  updated_at timestamptz not null default now(),
  unique (user_id, session_id)
);

create index if not exists idx_tap_game_scores_session_score
  on public.tap_game_scores (session_id, score desc);

create table if not exists public.tap_game_actions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  session_id uuid references public.tap_game_sessions(id) on delete set null,
  action_type text not null check (action_type in ('tap', 'boost', 'jump', 'shield')),
  value int,
  created_at timestamptz not null default now()
);

create index if not exists idx_tap_game_actions_user_created
  on public.tap_game_actions (user_id, created_at desc);

create table if not exists public.tap_game_reward_claims (
  session_id uuid not null references public.tap_game_sessions(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  rank int not null,
  amount int not null,
  created_at timestamptz not null default now(),
  primary key (session_id, user_id)
);

alter table public.tap_game_sessions enable row level security;
alter table public.tap_game_scores enable row level security;
alter table public.tap_game_actions enable row level security;
alter table public.tap_game_reward_claims enable row level security;

drop policy if exists tap_game_sessions_select on public.tap_game_sessions;
create policy tap_game_sessions_select on public.tap_game_sessions
  for select to authenticated using (true);

drop policy if exists tap_game_scores_select on public.tap_game_scores;
create policy tap_game_scores_select on public.tap_game_scores
  for select to authenticated using (true);

drop policy if exists tap_game_reward_claims_own on public.tap_game_reward_claims;
create policy tap_game_reward_claims_own on public.tap_game_reward_claims
  for select to authenticated using (user_id = (select auth.uid()));

-- Запись только через SECURITY DEFINER RPC (ниже).

-- ── Закрыть истекшие сессии ─────────────────────────────────────────────
create or replace function public.tap_game_expire_old_sessions()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.tap_game_sessions
  set is_active = false
  where is_active = true and ends_at <= now();
end;
$$;

-- ── Текущая или новая сессия (10 минут) ──────────────────────────────────
create or replace function public.tap_game_get_or_create_session()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  perform public.tap_game_expire_old_sessions();

  select id into v_id
  from public.tap_game_sessions
  where is_active = true and ends_at > now()
  order by started_at desc
  limit 1;

  if v_id is not null then
    return v_id;
  end if;

  insert into public.tap_game_sessions (ends_at, is_active)
  values (now() + interval '10 minutes', true)
  returning id into v_id;

  return v_id;
end;
$$;

-- ── Тапы: токен-бакет ~10/сек, при щите выше потолок и refill ────────────
create or replace function public.tap_game_add_score(p_session_id uuid, p_delta int)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
  v_row public.tap_game_scores%rowtype;
  v_elapsed numeric;
  v_new_burst numeric;
  v_rate numeric := 10;
  v_max_burst numeric := 15;
  v_new_score int;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;
  if p_delta is null or p_delta < 1 or p_delta > 2 then
    raise exception 'invalid_delta';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found then
    raise exception 'no_session';
  end if;
  if not v_sess.is_active or now() >= v_sess.ends_at then
    raise exception 'session_closed';
  end if;

  if p_delta = 2 then
    if not exists (
      select 1 from public.tap_game_scores s
      where s.user_id = v_user
        and s.session_id = p_session_id
        and s.boost_ends_at is not null
        and s.boost_ends_at > now()
    ) then
      raise exception 'no_boost';
    end if;
  end if;

  insert into public.tap_game_scores (
    user_id, session_id, score, burst_balance, updated_at
  )
  values (v_user, p_session_id, 0, 15, now())
  on conflict (user_id, session_id) do nothing;

  select * into v_row
  from public.tap_game_scores
  where user_id = v_user and session_id = p_session_id
  for update;

  if v_row.shield_ends_at is not null and v_row.shield_ends_at > now() then
    v_max_burst := 25;
    v_rate := 12;
  end if;

  v_elapsed := extract(epoch from (now() - v_row.updated_at));
  v_new_burst := least(
    v_max_burst,
    coalesce(v_row.burst_balance, 0)::numeric + v_elapsed * v_rate
  );

  if v_new_burst < p_delta then
    raise exception 'rate_limited';
  end if;

  v_new_burst := v_new_burst - p_delta;
  v_new_score := v_row.score + p_delta;

  update public.tap_game_scores
  set
    score = v_new_score,
    burst_balance = v_new_burst,
    updated_at = now()
  where user_id = v_user and session_id = p_session_id;

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'tap', p_delta);

  return v_new_score;
end;
$$;

-- ── После spend_qarmet на клиенте: буст x2 на 30 с ───────────────────────
create or replace function public.tap_game_apply_boost(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found or not v_sess.is_active or now() >= v_sess.ends_at then
    raise exception 'session_closed';
  end if;

  insert into public.tap_game_scores (
    user_id, session_id, score, burst_balance,
    boost_ends_at, updated_at
  )
  values (v_user, p_session_id, 0, 15, now() + interval '30 seconds', now())
  on conflict (user_id, session_id) do update set
    boost_ends_at = greatest(
      coalesce(public.tap_game_scores.boost_ends_at, now()),
      now()
    ) + interval '30 seconds',
    updated_at = now();

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'boost', 30);
end;
$$;

-- ── +1000 очков (после оплаты на клиенте), анти-спам ─────────────────────
create or replace function public.tap_game_apply_jump(p_session_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
  v_row public.tap_game_scores%rowtype;
  v_new int;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found or not v_sess.is_active or now() >= v_sess.ends_at then
    raise exception 'session_closed';
  end if;

  insert into public.tap_game_scores (
    user_id, session_id, score, burst_balance, updated_at
  )
  values (v_user, p_session_id, 0, 15, now())
  on conflict (user_id, session_id) do nothing;

  select * into v_row
  from public.tap_game_scores
  where user_id = v_user and session_id = p_session_id
  for update;

  if v_row.jump_last_at is not null
     and now() - v_row.jump_last_at < interval '45 seconds' then
    raise exception 'jump_cooldown';
  end if;

  v_new := v_row.score + 1000;

  update public.tap_game_scores
  set
    score = v_new,
    jump_last_at = now(),
    updated_at = now()
  where user_id = v_user and session_id = p_session_id;

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'jump', 1000);

  return v_new;
end;
$$;

-- ── Щит 5 мин (улучшенный бакет + фикс пола для UI) ──────────────────────
create or replace function public.tap_game_apply_shield(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found or not v_sess.is_active or now() >= v_sess.ends_at then
    raise exception 'session_closed';
  end if;

  insert into public.tap_game_scores (
    user_id, session_id, score, burst_balance, updated_at
  )
  values (v_user, p_session_id, 0, 15, now())
  on conflict (user_id, session_id) do nothing;

  update public.tap_game_scores
  set
    shield_ends_at = now() + interval '5 minutes',
    shield_floor = score,
    updated_at = now()
  where user_id = v_user and session_id = p_session_id;

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'shield', 5);
end;
$$;

-- ── Зафиксировать окончание сессии ───────────────────────────────────────
create or replace function public.tap_game_finalize_session(p_session_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.tap_game_expire_old_sessions();

  update public.tap_game_sessions
  set is_active = false
  where id = p_session_id
    and ends_at <= now();
end;
$$;

-- ── Награда топ-3 (кредит текущему пользователю, idempotent) ─────────────
create or replace function public.tap_game_claim_my_reward(p_session_id uuid)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
  v_rank int;
  v_amount int := 0;
  v_ins int;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found then
    raise exception 'no_session';
  end if;

  if now() < v_sess.ends_at then
    raise exception 'session_not_finished';
  end if;

  update public.tap_game_sessions
  set is_active = false
  where id = p_session_id;

  select r into v_rank
  from (
    select
      s.user_id,
      row_number() over (
        order by s.score desc, s.updated_at asc, s.user_id asc
      ) as r
    from public.tap_game_scores s
    where s.session_id = p_session_id
  ) x
  where x.user_id = v_user;

  if v_rank is null then
    return 0;
  end if;

  if v_rank = 1 then
    v_amount := 500;
  elsif v_rank = 2 then
    v_amount := 300;
  elsif v_rank = 3 then
    v_amount := 100;
  else
    return 0;
  end if;

  insert into public.tap_game_reward_claims (session_id, user_id, rank, amount)
  values (p_session_id, v_user, v_rank, v_amount)
  on conflict (session_id, user_id) do nothing;
  get diagnostics v_ins = row_count;
  if v_ins = 0 then
    return 0;
  end if;

  perform public.credit_qarmet(
    v_amount,
    case v_rank
      when 1 then 'tap_game_reward_1st'
      when 2 then 'tap_game_reward_2nd'
      else 'tap_game_reward_3rd'
    end
  );

  return v_amount;
end;
$$;

revoke all on function public.tap_game_expire_old_sessions() from public;
revoke all on function public.tap_game_get_or_create_session() from public;
revoke all on function public.tap_game_add_score(uuid, int) from public;
revoke all on function public.tap_game_apply_boost(uuid) from public;
revoke all on function public.tap_game_apply_jump(uuid) from public;
revoke all on function public.tap_game_apply_shield(uuid) from public;
revoke all on function public.tap_game_finalize_session(uuid) from public;
revoke all on function public.tap_game_claim_my_reward(uuid) from public;

grant execute on function public.tap_game_get_or_create_session() to authenticated;
grant execute on function public.tap_game_add_score(uuid, int) to authenticated;
grant execute on function public.tap_game_apply_boost(uuid) to authenticated;
grant execute on function public.tap_game_apply_jump(uuid) to authenticated;
grant execute on function public.tap_game_apply_shield(uuid) to authenticated;
grant execute on function public.tap_game_finalize_session(uuid) to authenticated;
grant execute on function public.tap_game_claim_my_reward(uuid) to authenticated;

-- Опционально: Realtime для лидерборда
-- alter publication supabase_realtime add table public.tap_game_scores;
