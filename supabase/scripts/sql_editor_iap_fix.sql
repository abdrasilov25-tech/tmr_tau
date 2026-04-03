-- ============================================================
-- IAP / Монетизация: диагностика и исправление
-- Запускать в Supabase SQL Editor (вкладка за вкладкой)
-- ============================================================

-- ----------------------------------------------------------------
-- 1. ДИАГНОСТИКА: проверить колонки монетизации на таблице users
-- ----------------------------------------------------------------
select column_name, data_type, column_default, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'users'
  and column_name in (
    'qarmet_balance',
    'official_page_active',
    'official_page_last_credit_at',
    'profile_cosmetics_iap_forever',
    'profile_premium_badge',
    'profile_frame_level',
    'profile_badge_level',
    'premium_active',
    'premium_until',
    'seller_plan',
    'seller_verified_store',
    'is_verified'
  )
order by column_name;

-- ----------------------------------------------------------------
-- 2. ДИАГНОСТИКА: проверить что RPC функции существуют
-- ----------------------------------------------------------------
select routine_name, security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'credit_qarmet',
    'spend_qarmet',
    'credit_official_page_monthly_qarmet',
    'spend_qarmet_and_apply_product_promotion'
  )
order by routine_name;

-- ----------------------------------------------------------------
-- 3. ДИАГНОСТИКА: проверить колонки таблицы payment_orders
-- ----------------------------------------------------------------
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'payment_orders'
order by ordinal_position;

-- ----------------------------------------------------------------
-- 4. ИСПРАВЛЕНИЕ: добавить недостающие колонки монетизации
--    (безопасно — IF NOT EXISTS)
-- ----------------------------------------------------------------
alter table public.users
  add column if not exists qarmet_balance          integer      not null default 0,
  add column if not exists official_page_active    boolean      not null default false,
  add column if not exists official_page_last_credit_at timestamptz,
  add column if not exists profile_cosmetics_iap_forever boolean not null default false,
  add column if not exists profile_premium_badge   boolean      not null default false,
  add column if not exists profile_frame_level     integer      not null default 0,
  add column if not exists profile_badge_level     integer      not null default 0,
  add column if not exists premium_active          boolean      not null default false,
  add column if not exists premium_until           timestamptz,
  add column if not exists seller_plan             text         not null default 'free',
  add column if not exists seller_verified_store   boolean      not null default false,
  add column if not exists is_verified             boolean      not null default false,
  add column if not exists official_page_profile_perks boolean  not null default false,
  add column if not exists official_page_promo_perks   boolean  not null default false;

-- seller_plan constraint
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'users_seller_plan_allowed_values'
      and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_seller_plan_allowed_values
      check (seller_plan in ('free', 'standard', 'pro'));
  end if;
end $$;

-- ----------------------------------------------------------------
-- 5. ИСПРАВЛЕНИЕ: пересоздать RPC credit_qarmet
-- ----------------------------------------------------------------
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
  v_next    int;
begin
  if v_user_id is null then raise exception 'unauthorized'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_credit_amount'; end if;

  update public.users
  set qarmet_balance = qarmet_balance + p_amount,
      updated_at     = now()
  where id = v_user_id
  returning qarmet_balance into v_next;

  if v_next is null then raise exception 'user_not_found'; end if;
  return v_next;
end;
$$;

revoke all on function public.credit_qarmet(int, text) from public;
grant execute on function public.credit_qarmet(int, text) to authenticated;

-- ----------------------------------------------------------------
-- 6. ИСПРАВЛЕНИЕ: пересоздать RPC spend_qarmet
-- ----------------------------------------------------------------
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
  v_next    int;
begin
  if v_user_id is null then raise exception 'unauthorized'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'invalid_spend_amount'; end if;

  select qarmet_balance into v_balance
  from public.users
  where id = v_user_id
  for update;

  if v_balance is null then raise exception 'user_not_found'; end if;
  if v_balance < p_amount then raise exception 'insufficient_qarmet'; end if;

  v_next := v_balance - p_amount;
  update public.users
  set qarmet_balance = v_next,
      updated_at     = now()
  where id = v_user_id;

  return v_next;
end;
$$;

revoke all on function public.spend_qarmet(int, text) from public;
grant execute on function public.spend_qarmet(int, text) to authenticated;

-- ----------------------------------------------------------------
-- 7. ИСПРАВЛЕНИЕ: пересоздать credit_official_page_monthly_qarmet
-- ----------------------------------------------------------------
create or replace function public.credit_official_page_monthly_qarmet()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id        uuid        := auth.uid();
  v_now            timestamptz := now();
  v_active         boolean;
  v_last_credit_at timestamptz;
  v_balance        int;
  v_months_passed  int         := 0;
  v_monthly_credit int         := 25;
  v_credit_amount  int         := 0;
  v_next           int;
begin
  if v_user_id is null then raise exception 'unauthorized'; end if;

  select official_page_active, official_page_last_credit_at, qarmet_balance
    into v_active, v_last_credit_at, v_balance
  from public.users
  where id = v_user_id
  for update;

  if v_balance is null then raise exception 'user_not_found'; end if;
  if coalesce(v_active, false) = false then return v_balance; end if;

  -- Первый вход после активации: просто зафиксировать дату
  if v_last_credit_at is null then
    update public.users
    set official_page_last_credit_at = v_now, updated_at = now()
    where id = v_user_id
    returning qarmet_balance into v_next;
    return v_next;
  end if;

  v_months_passed := floor(extract(epoch from (v_now - v_last_credit_at)) / (30.0 * 24 * 60 * 60));
  if v_months_passed <= 0 then return v_balance; end if;

  v_credit_amount := v_monthly_credit * v_months_passed;
  v_next          := v_balance + v_credit_amount;

  update public.users
  set qarmet_balance               = v_next,
      official_page_last_credit_at = v_now,
      updated_at                   = now()
  where id = v_user_id;

  return v_next;
end;
$$;

revoke all on function public.credit_official_page_monthly_qarmet() from public;
grant execute on function public.credit_official_page_monthly_qarmet() to authenticated;

-- ----------------------------------------------------------------
-- 8. ИСПРАВЛЕНИЕ: создать таблицу payment_orders если не существует
-- ----------------------------------------------------------------
create table if not exists public.payment_orders (
  id                  uuid        primary key default gen_random_uuid(),
  user_id             uuid        not null references public.users(id) on delete cascade,
  provider            text        not null default 'iap',
  kind                text        not null,   -- 'subscription' | 'boost' | 'cosmetics_forever'
  plan_code           text        not null,   -- product ID из App Store / Google Play
  amount_minor        integer     not null default 0,
  currency            text        not null default 'KZT',
  status              text        not null default 'pending',
  provider_payment_id text,
  provider_payload    jsonb,
  paid_at             timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- RLS
alter table public.payment_orders enable row level security;

do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'payment_orders' and policyname = 'Users can read own orders'
  ) then
    create policy "Users can read own orders"
      on public.payment_orders for select
      using (auth.uid() = user_id);
  end if;
end $$;

-- Запрет на прямую вставку/изменение из клиента — только через edge function (service role)
do $$ begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'payment_orders' and policyname = 'No direct client insert'
  ) then
    create policy "No direct client insert"
      on public.payment_orders for insert
      with check (false);
  end if;
end $$;

-- ----------------------------------------------------------------
-- 9. ИСПРАВЛЕНИЕ: обновить комментарий колонки profile_cosmetics_iap_forever
-- ----------------------------------------------------------------
comment on column public.users.profile_cosmetics_iap_forever is
  'Разовая покупка IAP (com.bazar.tmrtau.premium): оформление профиля и стикеры без списания Qarmet.';

-- ----------------------------------------------------------------
-- 10. ПРОВЕРКА: результат (баланс тестового пользователя)
-- ----------------------------------------------------------------
-- Замени 'your-user-id' на реальный UUID для теста
-- select id, qarmet_balance, official_page_active, profile_cosmetics_iap_forever,
--        premium_active, seller_plan
-- from public.users
-- where id = 'your-user-id';
