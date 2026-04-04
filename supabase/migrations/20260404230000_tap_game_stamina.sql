-- Энергия тапов за сессию + покупка продолжения за Qarmet (через spend_qarmet).
-- tap_game_add_score теперь возвращает json: { "score", "stamina" }.

alter table public.tap_game_scores
  add column if not exists stamina_remaining int not null default 180;

alter table public.tap_game_actions
  drop constraint if exists tap_game_actions_action_type_check;

alter table public.tap_game_actions
  add constraint tap_game_actions_action_type_check
  check (action_type in ('tap', 'boost', 'jump', 'shield', 'stamina'));

-- ── Тапы: токен-бакет + расход энергии ───────────────────────────────────
create or replace function public.tap_game_add_score(p_session_id uuid, p_delta int)
returns json
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
  v_stamina int;
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
    user_id, session_id, score, burst_balance, stamina_remaining, updated_at
  )
  values (v_user, p_session_id, 0, 15, 180, now())
  on conflict (user_id, session_id) do nothing;

  select * into v_row
  from public.tap_game_scores
  where user_id = v_user and session_id = p_session_id
  for update;

  if coalesce(v_row.stamina_remaining, 0) < p_delta then
    raise exception 'insufficient_stamina';
  end if;

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
  v_stamina := v_row.stamina_remaining - p_delta;

  update public.tap_game_scores
  set
    score = v_new_score,
    burst_balance = v_new_burst,
    stamina_remaining = v_stamina,
    updated_at = now()
  where user_id = v_user and session_id = p_session_id;

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'tap', p_delta);

  return json_build_object('score', v_new_score, 'stamina', v_stamina);
end;
$$;

-- ── Докупка энергии (атомарно: spend_qarmet + начисление тапов) ───────────
create or replace function public.tap_game_purchase_stamina(p_session_id uuid, p_tier int)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_sess public.tap_game_sessions%rowtype;
  v_row public.tap_game_scores%rowtype;
  v_cost int;
  v_add int;
  v_stamina_total int;
begin
  if v_user is null then
    raise exception 'unauthorized';
  end if;

  if p_tier = 1 then
    v_cost := 15;
    v_add := 150;
  elsif p_tier = 2 then
    v_cost := 39;
    v_add := 420;
  elsif p_tier = 3 then
    v_cost := 89;
    v_add := 1100;
  else
    raise exception 'invalid_stamina_tier';
  end if;

  select * into v_sess from public.tap_game_sessions where id = p_session_id;
  if not found or not v_sess.is_active or now() >= v_sess.ends_at then
    raise exception 'session_closed';
  end if;

  perform public.spend_qarmet(
    v_cost,
    'tap_game_stamina_tier_' || p_tier::text
  );

  insert into public.tap_game_scores (
    user_id, session_id, score, burst_balance, stamina_remaining, updated_at
  )
  values (v_user, p_session_id, 0, 15, 180, now())
  on conflict (user_id, session_id) do nothing;

  select * into v_row
  from public.tap_game_scores
  where user_id = v_user and session_id = p_session_id
  for update;

  v_stamina_total := v_row.stamina_remaining + v_add;

  update public.tap_game_scores
  set
    stamina_remaining = v_stamina_total,
    updated_at = now()
  where user_id = v_user and session_id = p_session_id;

  insert into public.tap_game_actions (user_id, session_id, action_type, value)
  values (v_user, p_session_id, 'stamina', v_add);

  return json_build_object(
    'stamina', v_stamina_total,
    'added', v_add,
    'spent', v_cost
  );
end;
$$;

revoke all on function public.tap_game_purchase_stamina(uuid, int) from public;
grant execute on function public.tap_game_purchase_stamina(uuid, int) to authenticated;
