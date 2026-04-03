-- Пожизненный IAP «оформление профиля»: рамки, значки, галочка + стикеры на карте (флаг на users).
alter table public.users
  add column if not exists profile_cosmetics_iap_forever boolean not null default false;

comment on column public.users.profile_cosmetics_iap_forever is
  'Разовая покупка IAP (com.bazar.tmrtau.premium): оформление профиля и стикеры без списания Qarmet.';
