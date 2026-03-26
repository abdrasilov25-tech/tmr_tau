alter table public.users
  add column if not exists city text default '';

alter table public.users
  add column if not exists instagram_url text default '';

alter table public.users
  add column if not exists telegram_username text default '';

alter table public.users
  add column if not exists website_url text default '';
