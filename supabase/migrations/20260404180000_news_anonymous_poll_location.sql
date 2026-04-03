-- Новости: анонимная публикация, подпись места, опрос (голоса отдельно).

alter table public.posts
  add column if not exists is_anonymous boolean not null default false;

alter table public.posts
  add column if not exists location_label text;

alter table public.posts
  add column if not exists poll_question text;

alter table public.posts
  add column if not exists poll_options text[];

comment on column public.posts.is_anonymous is 'Показывать пост без имени автора (user_id хранится для модерации).';
comment on column public.posts.location_label is 'Текстовая метка места для карточки новости.';
comment on column public.posts.poll_question is 'Вопрос опроса; голоса в post_poll_votes.';
comment on column public.posts.poll_options is 'Варианты ответа опроса (2–8 строк).';

create table if not exists public.post_poll_votes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  option_index int not null,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id),
  constraint post_poll_votes_option_non_negative check (option_index >= 0)
);

create index if not exists idx_post_poll_votes_post on public.post_poll_votes (post_id);

alter table public.post_poll_votes enable row level security;

drop policy if exists "post_poll_votes_select" on public.post_poll_votes;
create policy "post_poll_votes_select"
  on public.post_poll_votes for select
  using (true);

drop policy if exists "post_poll_votes_insert" on public.post_poll_votes;
create policy "post_poll_votes_insert"
  on public.post_poll_votes for insert
  with check (auth.uid() = user_id);

drop policy if exists "post_poll_votes_update" on public.post_poll_votes;
create policy "post_poll_votes_update"
  on public.post_poll_votes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
