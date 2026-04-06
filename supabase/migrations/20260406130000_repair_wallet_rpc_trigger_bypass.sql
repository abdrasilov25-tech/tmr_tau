-- Повторное применение: на части окружений остались RPC без
-- set_config('app.allow_managed_user_row_update', ...), из-за чего триггер
-- trg_prevent_self_assign_official_or_verified_flags режет credit_qarmet / spend_qarmet
-- с ошибкой: forbidden: paid official/verification flags are managed by backend only

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

revoke all on function public.credit_qarmet(int, text) from public;
revoke all on function public.spend_qarmet(int, text) from public;
revoke all on function public.credit_official_page_monthly_qarmet() from public;
grant execute on function public.credit_qarmet(int, text) to authenticated;
grant execute on function public.spend_qarmet(int, text) to authenticated;
grant execute on function public.credit_official_page_monthly_qarmet() to authenticated;
