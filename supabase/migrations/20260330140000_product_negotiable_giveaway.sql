-- Флаги «торг» и «отдам даром» для объявлений (как на OLX / маркетах РК).
alter table public.products add column if not exists is_negotiable boolean not null default false;
alter table public.products add column if not exists is_giveaway boolean not null default false;

create index if not exists idx_products_is_giveaway on public.products (is_giveaway) where is_giveaway = true;
create index if not exists idx_products_is_negotiable on public.products (is_negotiable) where is_negotiable = true;
