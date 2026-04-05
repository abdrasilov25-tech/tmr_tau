-- ============================================================================
-- Supabase SQL Editor: сторис — длительность видео и стикер «Музыка»
-- Идемпотентно (можно выполнять повторно). Не удаляет данные.
-- Аналог миграции: supabase/migrations/20260405190000_stories_music_and_duration.sql
-- ============================================================================

alter table public.stories
  add column if not exists video_duration_seconds int not null default 0;

alter table public.stories
  add column if not exists music_title text;

alter table public.stories
  add column if not exists music_artist text;

alter table public.stories
  add column if not exists music_external_url text;

-- Проверка (опционально):
-- select id, video_duration_seconds, music_title, music_artist,
--        left(music_external_url, 48) as music_url_preview
-- from public.stories
-- order by created_at desc
-- limit 10;
