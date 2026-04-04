-- Триггер trg_prevent_self_assign_verified_badges блокировал RPC credit_qarmet / spend_qarmet:
-- при UPDATE users из SECURITY DEFINER auth.uid() всё ещё пользователь, условие срабатывало.
-- Обход: доверенные функции выставляют app.allow_managed_user_row_update = '1' (на транзакцию).

create or replace function public.prevent_self_assign_official_or_verified_flags()
returns trigger
language plpgsql
as $$
begin
  if nullif(trim(both from coalesce(
        current_setting('app.allow_managed_user_row_update', true),
        ''
      )), '') = '1' then
    return new;
  end if;

  if auth.role() = 'authenticated'
     and auth.uid() is not null
     and new.id = auth.uid()
     and (
       coalesce(new.is_verified, false) is distinct from coalesce(old.is_verified, false)
       or coalesce(new.official_page_active, false) is distinct from coalesce(old.official_page_active, false)
       or coalesce(new.official_page_profile_perks, false) is distinct from coalesce(old.official_page_profile_perks, false)
       or coalesce(new.official_page_promo_perks, false) is distinct from coalesce(old.official_page_promo_perks, false)
       or coalesce(new.official_page_last_credit_at, to_timestamp(0)) is distinct from coalesce(old.official_page_last_credit_at, to_timestamp(0))
       or coalesce(new.seller_verified_store, false) is distinct from coalesce(old.seller_verified_store, false)
       or coalesce(new.seller_plan, 'free') is distinct from coalesce(old.seller_plan, 'free')
       or coalesce(new.seller_extended_stats, false) is distinct from coalesce(old.seller_extended_stats, false)
       or coalesce(new.qarmet_balance, 0) is distinct from coalesce(old.qarmet_balance, 0)
     ) then
    raise exception 'forbidden: paid official/verification flags are managed by backend only';
  end if;

  return new;
end;
$$;

create or replace function public.credit_qarmet(
  p_amount int,
  p_reason text default 'manual_credit'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_next int;
begin
  perform set_config('app.allow_managed_user_row_update', '1', true);

  if v_user_id is null then
    raise exception 'unauthorized';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_credit_amount';
  end if;

  update public.users
  set qarmet_balance = qarmet_balance + p_amount,
      updated_at = now()
  where id = v_user_id
  returning qarmet_balance into v_next;

  if v_next is null then
    raise exception 'user_not_found';
  end if;

  return v_next;
end;
$$;

create or replace function public.spend_qarmet(
  p_amount int,
  p_reason text default 'manual_spend'
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_balance int;
  v_next int;
begin
  perform set_config('app.allow_managed_user_row_update', '1', true);

  if v_user_id is null then
    raise exception 'unauthorized';
  end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'invalid_spend_amount';
  end if;

  select qarmet_balance into v_balance
  from public.users
  where id = v_user_id
  for update;

  if v_balance is null then
    raise exception 'user_not_found';
  end if;
  if v_balance < p_amount then
    raise exception 'insufficient_qarmet';
  end if;

  v_next := v_balance - p_amount;
  update public.users
  set qarmet_balance = v_next,
      updated_at = now()
  where id = v_user_id;

  return v_next;
end;
$$;

create or replace function public.credit_official_page_monthly_qarmet()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_now timestamptz := now();
  v_active boolean;
  v_last_credit_at timestamptz;
  v_balance int;
  v_months_passed int := 0;
  v_monthly_credit int := 25;
  v_credit_amount int := 0;
  v_next int;
begin
  perform set_config('app.allow_managed_user_row_update', '1', true);

  if v_user_id is null then
    raise exception 'unauthorized';
  end if;

  select official_page_active, official_page_last_credit_at, qarmet_balance
    into v_active, v_last_credit_at, v_balance
  from public.users
  where id = v_user_id
  for update;

  if v_balance is null then
    raise exception 'user_not_found';
  end if;
  if coalesce(v_active, false) = false then
    return v_balance;
  end if;

  if v_last_credit_at is null then
    update public.users
    set official_page_last_credit_at = v_now,
        updated_at = now()
    where id = v_user_id
    returning qarmet_balance into v_next;
    return v_next;
  end if;

  v_months_passed := floor(extract(epoch from (v_now - v_last_credit_at)) / (30 * 24 * 60 * 60));
  if v_months_passed <= 0 then
    return v_balance;
  end if;

  v_credit_amount := v_monthly_credit * v_months_passed;
  v_next := v_balance + v_credit_amount;

  update public.users
  set qarmet_balance = v_next,
      official_page_last_credit_at = v_now,
      updated_at = now()
  where id = v_user_id;

  return v_next;
end;
$$;

create or replace function public.spend_qarmet_and_apply_product_promotion(
  p_product_id uuid,
  p_kind text,
  p_cost int default 1,
  p_duration_hours int default 24
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid;
  v_balance int;
  v_now timestamptz;
  v_top_base timestamptz;
  v_urgent_base timestamptz;
  v_highlight_base timestamptz;
begin
  perform set_config('app.allow_managed_user_row_update', '1', true);

  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Пользователь не авторизован';
  end if;

  if p_cost <= 0 then
    raise exception 'Стоимость продвижения должна быть больше 0';
  end if;
  if p_duration_hours <= 0 then
    raise exception 'Длительность продвижения должна быть больше 0';
  end if;
  if p_kind not in ('top', 'urgent', 'highlight', 'all_in_one') then
    raise exception 'Неизвестный тип продвижения: %', p_kind;
  end if;

  perform 1
  from public.products p
  where p.id = p_product_id
    and p.seller_id = v_uid
  for update;

  if not found then
    raise exception 'Продвижение доступно только владельцу товара';
  end if;

  select u.qarmet_balance
    into v_balance
  from public.users u
  where u.id = v_uid
  for update;

  if v_balance is null then
    raise exception 'Профиль пользователя не найден';
  end if;

  if v_balance < p_cost then
    raise exception 'Недостаточно Qarmet. Нужно: %, доступно: %', p_cost, v_balance;
  end if;

  update public.users
  set qarmet_balance = v_balance - p_cost
  where id = v_uid;

  v_now := now();

  if p_kind = 'top' then
    select case
      when p.promo_top_until is not null and p.promo_top_until > v_now
        then p.promo_top_until
      else v_now
    end
    into v_top_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_top = true,
        promo_top_until = v_top_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  elsif p_kind = 'urgent' then
    select case
      when p.promo_urgent_until is not null and p.promo_urgent_until > v_now
        then p.promo_urgent_until
      else v_now
    end
    into v_urgent_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_urgent = true,
        promo_urgent_until = v_urgent_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  elsif p_kind = 'highlight' then
    select case
      when p.promo_highlight_until is not null and p.promo_highlight_until > v_now
        then p.promo_highlight_until
      else v_now
    end
    into v_highlight_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set promo_highlight_until = v_highlight_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  else
    select
      case
        when p.promo_top_until is not null and p.promo_top_until > v_now
          then p.promo_top_until
        else v_now
      end,
      case
        when p.promo_urgent_until is not null and p.promo_urgent_until > v_now
          then p.promo_urgent_until
        else v_now
      end,
      case
        when p.promo_highlight_until is not null and p.promo_highlight_until > v_now
          then p.promo_highlight_until
        else v_now
      end
    into v_top_base, v_urgent_base, v_highlight_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_top = true,
        is_urgent = true,
        promo_top_until = v_top_base + make_interval(hours => p_duration_hours),
        promo_urgent_until = v_urgent_base + make_interval(hours => p_duration_hours),
        promo_highlight_until = v_highlight_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;
  end if;
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
  perform set_config('app.allow_managed_user_row_update', '1', true);

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

revoke all on function public.credit_qarmet(int, text) from public;
revoke all on function public.spend_qarmet(int, text) from public;
revoke all on function public.credit_official_page_monthly_qarmet() from public;
grant execute on function public.credit_qarmet(int, text) to authenticated;
grant execute on function public.spend_qarmet(int, text) to authenticated;
grant execute on function public.credit_official_page_monthly_qarmet() to authenticated;

revoke all on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) from public;
grant execute on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) to authenticated;
