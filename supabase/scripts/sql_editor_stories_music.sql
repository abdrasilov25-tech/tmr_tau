-- =============================================================================
-- Supabase → SQL Editor: готовый скрипт для таблицы public.stories
--
-- Назначение: длительность видео, музыка, JSON стикеров на кадре.
-- Идемпотентно: можно выполнять повторно, данные не удаляются.
-- Условие: таблица public.stories уже существует (схема проекта tmr_tau).
-- Аналог миграции: supabase/migrations/20260405190000_stories_music_and_duration.sql
-- =============================================================================

alter table public.stories
  add column if not exists video_duration_seconds int not null default 0;

alter table public.stories
  add column if not exists music_title text;

alter table public.stories
  add column if not exists music_artist text;

alter table public.stories
  add column if not exists music_external_url text;

comment on column public.stories.video_duration_seconds is
  'Длительность видео в секундах (сторис / отображение).';

comment on column public.stories.music_title is
  'Название трека для стикера «Музыка» в сторис.';

comment on column public.stories.music_artist is
  'Исполнитель (стикер «Музыка»).';

comment on column public.stories.music_external_url is
  'URL превью трека (опционально, воспроизведение в приложении).';

alter table public.stories
  add column if not exists overlays_json text;

comment on column public.stories.overlays_json is
  'JSON-массив стикеров на кадре (тип, nx, ny, data).';

-- -----------------------------------------------------------------------------
-- Проверка: колонки музыки + overlays_json в метаданных
-- -----------------------------------------------------------------------------
select column_name
from information_schema.columns
where table_schema = 'public'
  and table_name = 'stories'
  and column_name in (
    'video_duration_seconds',
    'music_title',
    'music_artist',
    'music_external_url',
    'overlays_json'
  )
order by column_name;

-- -----------------------------------------------------------------------------
-- Опционально: последние сторис с музыкой (раскомментируйте при необходимости)
-- -----------------------------------------------------------------------------
-- select
--   id,
--   user_id,
--   video_duration_seconds,
--   music_title,
--   music_artist,
--   left(coalesce(music_external_url, ''), 64) as music_url_preview,
--   created_at
-- from public.stories
-- where music_title is not null
-- order by created_at desc
-- limit 20;
