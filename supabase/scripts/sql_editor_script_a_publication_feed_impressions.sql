-- ============================================================
-- Скрипт А — выполнить в Supabase SQL Editor ПЕРЕД миграцией
-- 20260328000001_add_recommendation_fields.sql
-- (иначе упадут UPDATE/триггер на publication_feed_impressions).
-- Требуются существующие таблицы public.users и public.posts.
-- ============================================================

create table if not exists public.publication_feed_impressions (
  user_id uuid not null references public.users(id) on delete cascade,
  post_id uuid not null references public.posts(id) on delete cascade,
  watched_ms int not null default 0,
  completed boolean not null default false,
  last_seen_at timestamptz default now(),
  primary key (user_id, post_id)
);

create index if not exists idx_publication_feed_impressions_user
  on public.publication_feed_impressions (user_id);

alter table public.publication_feed_impressions enable row level security;

drop policy if exists "Publication feed impressions select own" on public.publication_feed_impressions;
drop policy if exists "Publication feed impressions insert own" on public.publication_feed_impressions;
drop policy if exists "Publication feed impressions update own" on public.publication_feed_impressions;
drop policy if exists "Publication feed impressions delete own" on public.publication_feed_impressions;

create policy "Publication feed impressions select own"
  on public.publication_feed_impressions for select
  using (auth.uid() = user_id);

create policy "Publication feed impressions insert own"
  on public.publication_feed_impressions for insert
  with check (auth.uid() = user_id);

create policy "Publication feed impressions update own"
  on public.publication_feed_impressions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Publication feed impressions delete own"
  on public.publication_feed_impressions for delete
  using (auth.uid() = user_id);

create or replace function public.increment_publication_feed_impression(
  p_post_id uuid,
  p_delta_ms int default 0,
  p_completed boolean default false
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  insert into public.publication_feed_impressions (user_id, post_id, watched_ms, completed)
  values (
    auth.uid(),
    p_post_id,
    greatest(0, coalesce(p_delta_ms, 0)),
    coalesce(p_completed, false)
  )
  on conflict (user_id, post_id) do update set
    watched_ms = public.publication_feed_impressions.watched_ms
      + greatest(0, excluded.watched_ms),
    completed = public.publication_feed_impressions.completed or excluded.completed,
    last_seen_at = now();
end;
$$;

grant execute on function public.increment_publication_feed_impression(uuid, int, boolean) to authenticated;
