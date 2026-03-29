-- Apple / Google OAuth: профили в public.users
-- Выполни в Supabase → SQL Editor (можно повторно).
--
-- Важно: сами провайдеры включаются в Dashboard → Authentication → Providers
-- (Google: Client ID + Secret; Apple: Service ID, ключ и т.д.).
-- Redirect URLs: добавь tmrtau://auth/callback (и при необходимости URL веб-колбэка Supabase).

-- 1) Триггер: строка в public.users при любом новом auth.users (email, Apple, Google)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(trim(new.raw_user_meta_data->>'given_name'), ''),
    nullif(trim(new.email), ''),
    'Пользователь'
  );

  insert into public.users (id, name)
  values (new.id, v_name)
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2) Докачка профилей, если кто-то уже есть в auth.users, но нет строки в public.users
insert into public.users (id, name)
select
  au.id,
  coalesce(
    nullif(trim(au.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(au.raw_user_meta_data->>'name'), ''),
    nullif(trim(au.raw_user_meta_data->>'given_name'), ''),
    nullif(trim(au.email), ''),
    'Пользователь'
  )
from auth.users au
left join public.users u on u.id = au.id
where u.id is null;
