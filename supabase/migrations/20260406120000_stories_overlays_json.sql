alter table public.stories
  add column if not exists overlays_json text;

comment on column public.stories.overlays_json is
  'JSON-массив стикеров на кадре (тип, nx, ny, data).';
