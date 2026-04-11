-- Опциональная денормализация email из auth.users (клиент уже читает email из JWT при отсутствии колонки).
alter table public.users add column if not exists email text;

comment on column public.users.email is 'Опционально; основной источник — auth.users.';

-- Однократный backfill (SQL Editor / миграция под ролью postgres).
update public.users u
set email = au.email
from auth.users au
where u.id = au.id
  and au.email is not null
  and length(trim(au.email)) > 0
  and (u.email is null or trim(u.email) = '');
