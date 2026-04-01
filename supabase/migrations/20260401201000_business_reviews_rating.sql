create table if not exists public.business_reviews (
  id uuid primary key default gen_random_uuid(),
  business_user_id uuid not null references public.users(id) on delete cascade,
  reviewer_id uuid not null references public.users(id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  review_text text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint business_reviews_business_reviewer_unique
    unique (business_user_id, reviewer_id),
  constraint business_reviews_no_self_review
    check (business_user_id <> reviewer_id)
);

create index if not exists idx_business_reviews_business_user
  on public.business_reviews (business_user_id, created_at desc);

create index if not exists idx_business_reviews_reviewer
  on public.business_reviews (reviewer_id, created_at desc);

alter table public.business_reviews enable row level security;

drop policy if exists "Business reviews public read" on public.business_reviews;
create policy "Business reviews public read"
  on public.business_reviews
  for select
  using (true);

drop policy if exists "Business reviews insert own" on public.business_reviews;
create policy "Business reviews insert own"
  on public.business_reviews
  for insert
  with check (auth.uid() = reviewer_id);

drop policy if exists "Business reviews update own" on public.business_reviews;
create policy "Business reviews update own"
  on public.business_reviews
  for update
  using (auth.uid() = reviewer_id)
  with check (auth.uid() = reviewer_id);

drop policy if exists "Business reviews delete own" on public.business_reviews;
create policy "Business reviews delete own"
  on public.business_reviews
  for delete
  using (auth.uid() = reviewer_id);

create or replace function public.set_business_reviews_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_business_reviews_set_updated_at on public.business_reviews;
create trigger trg_business_reviews_set_updated_at
before update on public.business_reviews
for each row execute function public.set_business_reviews_updated_at();
