-- Музыка в сторис (как стикер / метаданные) + длительность видео для UI репоста.
alter table public.stories add column if not exists video_duration_seconds int not null default 0;
alter table public.stories add column if not exists music_title text;
alter table public.stories add column if not exists music_artist text;
alter table public.stories add column if not exists music_external_url text;

comment on column public.stories.video_duration_seconds is 'Длительность видео в секундах (отображение, напр. репост).';
comment on column public.stories.music_title is 'Название трека для стикера в сторис.';
comment on column public.stories.music_artist is 'Исполнитель.';
comment on column public.stories.music_external_url is 'Опциональная ссылка на превью/стрим (если подключите плеер).';
