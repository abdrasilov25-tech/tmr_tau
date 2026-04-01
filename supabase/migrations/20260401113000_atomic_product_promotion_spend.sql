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

revoke all on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) from public;
grant execute on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) to authenticated;
