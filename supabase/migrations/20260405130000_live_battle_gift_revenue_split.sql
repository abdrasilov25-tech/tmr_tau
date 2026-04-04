-- LIVE Battle gifts: начисление Qarmet ведущему + доля платформы (как комиссия TikTok).
-- Настройка: таблица platform_monetization_settings (одна строка id=1).
--   platform_recipient_user_id — uuid пользователя «кошелёк платформы» в public.users (создайте тех. аккаунт).
--   live_battle_gift_fee_bps — комиссия в базисных пунктах (3000 = 30%). Пока recipient null — 100% ведущему.

create table if not exists public.platform_monetization_settings (
  id smallint primary key default 1,
  live_battle_gift_fee_bps int not null default 3000
    check (live_battle_gift_fee_bps >= 0 and live_battle_gift_fee_bps < 10000),
  platform_recipient_user_id uuid references public.users (id) on delete set null,
  constraint platform_monetization_settings_singleton check (id = 1)
);

alter table public.platform_monetization_settings enable row level security;

insert into public.platform_monetization_settings (id, live_battle_gift_fee_bps, platform_recipient_user_id)
values (1, 3000, null)
on conflict (id) do nothing;

revoke all on table public.platform_monetization_settings from public;
grant all on table public.platform_monetization_settings to service_role;

alter table public.live_battle_events
  add column if not exists gift_host_credit int not null default 0;

alter table public.live_battle_events
  add column if not exists gift_platform_credit int not null default 0;

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
  v_fee_bps int := 0;
  v_platform_uid uuid;
  v_host_credit int;
  v_platform_credit int;
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

  select coalesce(s.live_battle_gift_fee_bps, 0), s.platform_recipient_user_id
  into v_fee_bps, v_platform_uid
  from public.platform_monetization_settings s
  where s.id = 1;

  if v_platform_uid is null then
    v_host_credit := v_price;
    v_platform_credit := 0;
  else
    v_host_credit := (v_price * (10000 - v_fee_bps)) / 10000;
    v_platform_credit := v_price - v_host_credit;
  end if;

  if v_host_credit > 0 then
    perform 1 from public.users where id = p_target_host for update;
    update public.users
    set qarmet_balance = qarmet_balance + v_host_credit
    where id = p_target_host;
  end if;

  if v_platform_credit > 0 then
    if v_platform_uid = p_target_host then
      raise exception 'platform_wallet_same_as_host';
    end if;
    perform 1 from public.users where id = v_platform_uid for update;
    update public.users
    set qarmet_balance = qarmet_balance + v_platform_credit
    where id = v_platform_uid;
  end if;

  v_points := v_price;
  if v_end_time - v_now <= interval '30 seconds' then
    v_points := v_points * 2;
  end if;

  insert into public.live_battle_events (
    battle_id,
    sender_id,
    target_host,
    event_type,
    gift_id,
    gift_price,
    points_awarded,
    gift_host_credit,
    gift_platform_credit
  ) values (
    p_battle_id,
    v_user_id,
    p_target_host,
    'gift',
    p_gift_id,
    v_price,
    v_points,
    v_host_credit,
    v_platform_credit
  );

  update public.live_battles
  set score_a = case when host_a = p_target_host then score_a + v_points else score_a end,
      score_b = case when host_b = p_target_host then score_b + v_points else score_b end,
      updated_at = v_now
  where id = p_battle_id;

  return v_points;
end;
$$;

revoke all on function public.send_live_battle_gift(uuid, text, uuid) from public;
grant execute on function public.send_live_battle_gift(uuid, text, uuid) to authenticated;
