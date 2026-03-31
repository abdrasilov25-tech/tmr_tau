alter table public.notifications
  add column if not exists story_id uuid references public.stories(id) on delete set null;

create index if not exists idx_notifications_story_id
  on public.notifications(story_id);

create index if not exists idx_notifications_type_created_at
  on public.notifications(type, created_at desc);
