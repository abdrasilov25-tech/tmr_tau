alter table public.stories
  add column if not exists original_post_id uuid references public.posts(id) on delete set null;

alter table public.stories
  add column if not exists original_post_author_id uuid references public.users(id) on delete set null;

alter table public.stories
  add column if not exists original_post_author_name text default '';

alter table public.stories
  add column if not exists original_post_preview_url text default '';
