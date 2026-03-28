-- ============================================================
-- Скрипт Б — таблица orders + RLS (корзина / оформление заказа).
-- Выполнить в Supabase SQL Editor, если таблицы orders нет.
-- Требуются public.users и public.products.
-- ============================================================

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  status text default 'pending',
  created_at timestamptz default now()
);

alter table public.orders enable row level security;

drop policy if exists "Orders all" on public.orders;
create policy "Orders all" on public.orders for all using (auth.uid() = buyer_id);
