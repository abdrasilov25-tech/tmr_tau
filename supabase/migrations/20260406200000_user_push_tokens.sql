-- Таблица FCM-токенов для server-side пушей (Edge Functions / внешний сервис).
create table if not exists public.user_push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  fcm_token text not null,
  platform text not null check (platform in ('android', 'ios', 'web', 'other')),
  updated_at timestamptz not null default now(),
  unique (user_id, fcm_token)
);

create index if not exists idx_user_push_tokens_user_id
  on public.user_push_tokens (user_id);

alter table public.user_push_tokens enable row level security;

drop policy if exists "user_push_tokens select own" on public.user_push_tokens;
create policy "user_push_tokens select own"
  on public.user_push_tokens for select
  using (auth.uid() = user_id);

drop policy if exists "user_push_tokens insert own" on public.user_push_tokens;
create policy "user_push_tokens insert own"
  on public.user_push_tokens for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_push_tokens update own" on public.user_push_tokens;
create policy "user_push_tokens update own"
  on public.user_push_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "user_push_tokens delete own" on public.user_push_tokens;
create policy "user_push_tokens delete own"
  on public.user_push_tokens for delete
  using (auth.uid() = user_id);
