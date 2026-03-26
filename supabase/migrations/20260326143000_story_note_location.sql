alter table public.users
  add column if not exists note_location text default '';

alter table public.users
  add column if not exists share_location boolean default false;
