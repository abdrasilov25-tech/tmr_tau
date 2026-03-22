-- =============================================================================
-- Платное продвижение товаров: сроки действия, просмотры, заказы оплаты.
-- Применить в Supabase SQL Editor или: supabase db push
-- =============================================================================

alter table public.products
  add column if not exists promo_top_until timestamptz;
alter table public.products
  add column if not exists promo_urgent_until timestamptz;
alter table public.products
  add column if not exists promo_highlight_until timestamptz;
alter table public.products
  add column if not exists stats_access_until timestamptz;
alter table public.products
  add column if not exists view_count int not null default 0;

comment on column public.products.promo_top_until is 'Платная метка «В топ» до указанного времени (UTC).';
comment on column public.products.promo_urgent_until is 'Платная метка «Срочно» до указанного времени (UTC).';
comment on column public.products.promo_highlight_until is 'Платное выделение рамкой/цветом до указанного времени (UTC).';
comment on column public.products.stats_access_until is 'Доступ продавца к статистике просмотров до указанного времени (UTC).';
comment on column public.products.view_count is 'Счётчик просмотров карточки (инкремент через RPC).';

create table if not exists public.product_promotion_orders (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products (id) on delete cascade,
  seller_id uuid not null references auth.users (id) on delete cascade,
  kind text not null check (kind in ('top', 'urgent', 'highlight', 'stats')),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'failed', 'cancelled')),
  provider text,
  provider_ref text,
  amount_minor int not null default 0,
  currency text not null default 'KZT',
  duration_hours int not null default 24,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  paid_at timestamptz
);

create index if not exists idx_product_promotion_orders_product
  on public.product_promotion_orders (product_id);
create index if not exists idx_product_promotion_orders_seller
  on public.product_promotion_orders (seller_id);

alter table public.product_promotion_orders enable row level security;

drop policy if exists "promo_orders_select_own" on public.product_promotion_orders;
create policy "promo_orders_select_own"
  on public.product_promotion_orders
  for select
  to authenticated
  using (auth.uid() = seller_id);

-- Вставка/обновление заказов и флагов — только через Edge Function (service role) или webhook.

-- -----------------------------------------------------------------------------
-- Публичный инкремент просмотров (без раскрытия данных продавца).
-- -----------------------------------------------------------------------------
create or replace function public.increment_product_view(p_product_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.products
  set view_count = coalesce(view_count, 0) + 1
  where id = p_product_id;
end;
$$;

grant execute on function public.increment_product_view(uuid) to anon, authenticated;
