-- =============================================================================
-- Аудит безопасности (Supabase SQL Editor)
-- =============================================================================
-- Зачем: проверить, что строки защищены RLS и нет «слишком открытых» политик.
--
-- Важно про «чужой аккаунт видит чужие данные»:
-- - RLS в PostgREST ограничивает доступ по JWT (auth.uid()). Она НЕ знает про
--   «аккаунт в приложении» — если один клиент кэширует UI или подставляет
--   не те id, это исправляется в приложении (сброс кэша при смене сессии).
-- - Политика SELECT на public.users с using (true) намеренно даёт всем
--   авторизованным читать профили (в т.ч. story_note для ленты/чатов). Если
--   нужно скрыть заметку от всех кроме владельца — нужна отдельная таблица
--   или VIEW и смена запросов в приложении (иначе сломается отображение чужих
--   заметок в полоске историй).
-- =============================================================================

-- 1) Таблицы в public без RLS (должно быть пусто для пользовательских данных)
select
  c.relname as table_name
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind = 'r'
  and not c.relrowsecurity
order by 1;

-- 2) Все политики public (обзор)
select
  tablename,
  policyname,
  cmd as command,
  roles,
  qual as using_expression,
  with_check as with_check_expression
from pg_policies
where schemaname = 'public'
order by tablename, cmd, policyname;

-- 3) SELECT-политики с полным доступом (qual выражает «всегда true»)
--    Вручную проверьте, что это оправдано для каждой таблицы.
select
  tablename,
  policyname,
  qual as using_expression
from pg_policies
where schemaname = 'public'
  and cmd = 'SELECT'
  and (
    qual is null
    or trim(both '()' from qual) in ('true', 'TRUE')
    or qual = '(true)'
  )
order by tablename;

-- 4) Усиление UPDATE на users (явный WITH CHECK) уже в миграции:
--    supabase/migrations/20260327130000_users_update_explicit_with_check.sql
