alter table public.orders
  add column if not exists seller_id uuid references public.users(id) on delete set null;

alter table public.orders
  add column if not exists product_title text default '';

alter table public.orders
  add column if not exists safe_purchase boolean not null default false;

alter table public.orders
  add column if not exists amount_kzt numeric(12,2) default 0;

alter table public.orders
  add column if not exists commission_percent int not null default 4;

alter table public.orders
  add column if not exists commission_kzt numeric(12,2) not null default 0;

alter table public.orders
  add column if not exists seller_amount_kzt numeric(12,2) not null default 0;

alter table public.orders
  add column if not exists seller_accepted_at timestamptz;

alter table public.orders
  add column if not exists buyer_confirmed_at timestamptz;

alter table public.orders
  add column if not exists completed_at timestamptz;

alter table public.orders
  add column if not exists cancelled_at timestamptz;

alter table public.orders
  add column if not exists updated_at timestamptz default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'orders_status_allowed_values'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_status_allowed_values
      check (status in ('pending_seller', 'in_escrow', 'completed', 'cancelled'));
  end if;
end $$;

create index if not exists idx_orders_buyer_created_at
  on public.orders (buyer_id, created_at desc);

create index if not exists idx_orders_seller_created_at
  on public.orders (seller_id, created_at desc);

drop policy if exists "Orders all" on public.orders;
drop policy if exists "Orders select participants" on public.orders;
drop policy if exists "Orders insert buyer" on public.orders;
drop policy if exists "Orders update participants" on public.orders;
drop policy if exists "Orders delete buyer" on public.orders;

create policy "Orders select participants"
  on public.orders for select
  using (auth.uid() = buyer_id or auth.uid() = seller_id);

create policy "Orders insert buyer"
  on public.orders for insert
  with check (auth.uid() = buyer_id);

create policy "Orders update participants"
  on public.orders for update
  using (auth.uid() = buyer_id or auth.uid() = seller_id)
  with check (auth.uid() = buyer_id or auth.uid() = seller_id);

create policy "Orders delete buyer"
  on public.orders for delete
  using (auth.uid() = buyer_id);
