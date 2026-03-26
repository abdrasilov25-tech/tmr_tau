alter table public.users
  add column if not exists story_note text default '';
