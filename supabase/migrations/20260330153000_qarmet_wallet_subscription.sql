-- Qarmet wallet + official_page subscription flags for user profile monetization.
alter table public.users
  add column if not exists qarmet_balance int not null default 0,
  add column if not exists official_page_active boolean not null default false,
  add column if not exists official_page_last_credit_at timestamptz,
  add column if not exists official_page_profile_perks boolean not null default false,
  add column if not exists official_page_promo_perks boolean not null default false,
  add column if not exists profile_premium_badge boolean not null default false,
  add column if not exists profile_frame_level int not null default 0,
  add column if not exists profile_badge_level int not null default 0;

create index if not exists idx_users_qarmet_balance
  on public.users (qarmet_balance);

create index if not exists idx_users_official_page_active
  on public.users (official_page_active)
  where official_page_active = true;
