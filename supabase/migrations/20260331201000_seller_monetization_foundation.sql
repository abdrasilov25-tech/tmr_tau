alter table public.users
  add column if not exists seller_plan text not null default 'free';

alter table public.users
  add column if not exists seller_verified_store boolean not null default false;

alter table public.users
  add column if not exists seller_extended_stats boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'users_seller_plan_allowed_values'
      and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_seller_plan_allowed_values
      check (seller_plan in ('free', 'standard', 'pro'));
  end if;
end $$;

-- Backward compatibility:
-- legacy paid sellers with official_page_active=true migrate to standard plan.
update public.users
set seller_plan = 'standard'
where official_page_active = true
  and coalesce(seller_plan, 'free') = 'free';
