-- Универсальные жалобы (посты, товары, профили и т.д.) для модерации.
create table if not exists public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.users (id) on delete cascade,
  target_type text not null,
  target_id text not null,
  reason text not null,
  comment text not null default '',
  meta jsonb,
  created_at timestamptz not null default now(),
  constraint reports_target_type_allowed check (
    target_type in (
      'post',
      'product',
      'user',
      'chat_message',
      'story',
      'other'
    )
  ),
  constraint reports_reason_len check (char_length(reason) >= 1 and char_length(reason) <= 512)
);

create index if not exists idx_reports_target on public.reports (target_type, target_id);
create index if not exists idx_reports_created_at on public.reports (created_at desc);

alter table public.reports enable row level security;

drop policy if exists "reports insert own" on public.reports;
create policy "reports insert own"
  on public.reports for insert
  with check (auth.uid() = reporter_id);

drop policy if exists "reports select own" on public.reports;
create policy "reports select own"
  on public.reports for select
  using (auth.uid() = reporter_id);
