-- Колонка для массива URL фото (jsonb). Выполни в Supabase → SQL → Run.
-- После этого перезапуск приложения не обязателен.

alter table public.products
  add column if not exists image_urls jsonb default '[]'::jsonb;

-- Опционально: перенести в jsonb старые данные, если в image_url был JSON-массив (несколько фото в одной строке).
-- Раскомментируй при необходимости:
-- update public.products p
-- set image_urls = (p.image_url)::jsonb
-- where trim(coalesce(p.image_url, '')) like '[%'
--   and (p.image_urls is null or p.image_urls = '[]'::jsonb);
