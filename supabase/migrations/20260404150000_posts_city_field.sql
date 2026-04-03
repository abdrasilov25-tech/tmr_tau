-- Add city column to posts for news city filtering
alter table public.posts
  add column if not exists city text;

-- Tag all existing news posts as Темиртау (app's founding city)
update public.posts
  set city = 'Темиртау'
  where city is null and kind = 'news';

-- Index for fast city filter queries
create index if not exists posts_city_kind_idx
  on public.posts(city, kind)
  where city is not null;
