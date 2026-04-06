-- Музыка поверх видео-публикаций (метаданные + URL превью из каталога, как в сторис).
alter table public.posts add column if not exists music_title text;
alter table public.posts add column if not exists music_artist text;
alter table public.posts add column if not exists music_preview_url text;
