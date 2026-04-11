-- tmr_tau — Marketplace + Social (Instagram/TikTok style)
-- Run in Supabase SQL Editor after creating a project

-- ============== USERS (profiles) ==============
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  avatar text,
  bio text,
  story_note text default '',
  note_location text default '',
  share_location boolean default false,
  followers_count int default 0,
  following_count int default 0,
  is_verified boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- If table already exists, add column: alter table public.users add column if not exists is_verified boolean default false;
alter table public.users add column if not exists story_note text default '';
alter table public.users add column if not exists note_location text default '';
alter table public.users add column if not exists share_location boolean default false;
alter table public.users add column if not exists city text default '';
alter table public.users add column if not exists email text;
alter table public.users add column if not exists instagram_url text default '';
alter table public.users add column if not exists telegram_username text default '';
alter table public.users add column if not exists website_url text default '';
alter table public.users add column if not exists total_received_post_likes int not null default 0;
alter table public.users add column if not exists qarmet_balance int not null default 0;
alter table public.users add column if not exists official_page_active boolean not null default false;
alter table public.users add column if not exists official_page_last_credit_at timestamptz;
alter table public.users add column if not exists official_page_profile_perks boolean not null default false;
alter table public.users add column if not exists official_page_promo_perks boolean not null default false;
alter table public.users add column if not exists profile_premium_badge boolean not null default false;
alter table public.users add column if not exists profile_frame_level int not null default 0;
alter table public.users add column if not exists profile_badge_level int not null default 0;
alter table public.users add column if not exists profile_cosmetics_iap_forever boolean not null default false;
alter table public.users add column if not exists last_active_at timestamptz;
alter table public.users add column if not exists seller_plan text not null default 'free';
alter table public.users add column if not exists seller_verified_store boolean not null default false;
alter table public.users add column if not exists seller_extended_stats boolean not null default false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'users_seller_plan_allowed_values'
      and conrelid = 'public.users'::regclass
  ) then
    alter table public.users
      add constraint users_seller_plan_allowed_values
      check (seller_plan in ('free', 'standard', 'pro'));
  end if;
end $$;
-- Backfill missing rows in public.users from auth.users (safe on repeated runs).
insert into public.users (id, name)
select au.id, coalesce(nullif(au.email, ''), 'Пользователь')
from auth.users au
left join public.users u on u.id = au.id
where u.id is null;

-- ============== CATEGORIES (категории и подкатегории товаров) ==============
create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  parent_id uuid references public.categories(id) on delete cascade
);

alter table public.categories enable row level security;
drop policy if exists "Categories select" on public.categories;
create policy "Categories select" on public.categories for select using (true);

-- Основные категории (по одной вставке, без сравнения uuid)
insert into public.categories (name, parent_id) select 'Транспорт', null where not exists (select 1 from public.categories where name = 'Транспорт' and parent_id is null);
insert into public.categories (name, parent_id) select 'Недвижимость', null where not exists (select 1 from public.categories where name = 'Недвижимость' and parent_id is null);
insert into public.categories (name, parent_id) select 'Электроника', null where not exists (select 1 from public.categories where name = 'Электроника' and parent_id is null);
insert into public.categories (name, parent_id) select 'Одежда, обувь, аксессуары', null where not exists (select 1 from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null);
insert into public.categories (name, parent_id) select 'Дом и сад', null where not exists (select 1 from public.categories where name = 'Дом и сад' and parent_id is null);
insert into public.categories (name, parent_id) select 'Хобби и отдых', null where not exists (select 1 from public.categories where name = 'Хобби и отдых' and parent_id is null);
insert into public.categories (name, parent_id) select 'Услуги', null where not exists (select 1 from public.categories where name = 'Услуги' and parent_id is null);
insert into public.categories (name, parent_id) select 'Работа', null where not exists (select 1 from public.categories where name = 'Работа' and parent_id is null);
insert into public.categories (name, parent_id) select 'Животные', null where not exists (select 1 from public.categories where name = 'Животные' and parent_id is null);
insert into public.categories (name, parent_id) select 'Для детей', null where not exists (select 1 from public.categories where name = 'Для детей' and parent_id is null);

-- Подкатегории
insert into public.categories (name, parent_id) select 'Легковые автомобили', id from public.categories where name = 'Транспорт' and parent_id is null and not exists (select 1 from public.categories where name = 'Легковые автомобили') limit 1;
insert into public.categories (name, parent_id) select 'Мотоциклы и скутеры', id from public.categories where name = 'Транспорт' and parent_id is null and not exists (select 1 from public.categories where name = 'Мотоциклы и скутеры') limit 1;
insert into public.categories (name, parent_id) select 'Грузовые автомобили', id from public.categories where name = 'Транспорт' and parent_id is null and not exists (select 1 from public.categories where name = 'Грузовые автомобили') limit 1;
insert into public.categories (name, parent_id) select 'Запчасти и аксессуары', id from public.categories where name = 'Транспорт' and parent_id is null and not exists (select 1 from public.categories where name = 'Запчасти и аксессуары') limit 1;

insert into public.categories (name, parent_id) select 'Квартиры', id from public.categories where name = 'Недвижимость' and parent_id is null and not exists (select 1 from public.categories where name = 'Квартиры') limit 1;
insert into public.categories (name, parent_id) select 'Дома и дачи', id from public.categories where name = 'Недвижимость' and parent_id is null and not exists (select 1 from public.categories where name = 'Дома и дачи') limit 1;
insert into public.categories (name, parent_id) select 'Коммерческая недвижимость', id from public.categories where name = 'Недвижимость' and parent_id is null and not exists (select 1 from public.categories where name = 'Коммерческая недвижимость') limit 1;
insert into public.categories (name, parent_id) select 'Земельные участки', id from public.categories where name = 'Недвижимость' and parent_id is null and not exists (select 1 from public.categories where name = 'Земельные участки') limit 1;

insert into public.categories (name, parent_id) select 'Мобильные телефоны', id from public.categories where name = 'Электроника' and parent_id is null and not exists (select 1 from public.categories where name = 'Мобильные телефоны') limit 1;
insert into public.categories (name, parent_id) select 'Компьютеры и ноутбуки', id from public.categories where name = 'Электроника' and parent_id is null and not exists (select 1 from public.categories where name = 'Компьютеры и ноутбуки') limit 1;
insert into public.categories (name, parent_id) select 'Телевизоры и аудио', id from public.categories where name = 'Электроника' and parent_id is null and not exists (select 1 from public.categories where name = 'Телевизоры и аудио') limit 1;
insert into public.categories (name, parent_id) select 'Фото и видео техника', id from public.categories where name = 'Электроника' and parent_id is null and not exists (select 1 from public.categories where name = 'Фото и видео техника') limit 1;

insert into public.categories (name, parent_id) select 'Женская одежда', id from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null and not exists (select 1 from public.categories where name = 'Женская одежда') limit 1;
insert into public.categories (name, parent_id) select 'Мужская одежда', id from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null and not exists (select 1 from public.categories where name = 'Мужская одежда') limit 1;
insert into public.categories (name, parent_id) select 'Детская одежда', id from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null and not exists (select 1 from public.categories where name = 'Детская одежда') limit 1;
insert into public.categories (name, parent_id) select 'Обувь', id from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null and not exists (select 1 from public.categories where name = 'Обувь') limit 1;
insert into public.categories (name, parent_id) select 'Сумки и аксессуары', id from public.categories where name = 'Одежда, обувь, аксессуары' and parent_id is null and not exists (select 1 from public.categories where name = 'Сумки и аксессуары') limit 1;

insert into public.categories (name, parent_id) select 'Мебель', id from public.categories where name = 'Дом и сад' and parent_id is null and not exists (select 1 from public.categories where name = 'Мебель') limit 1;
insert into public.categories (name, parent_id) select 'Бытовая техника', id from public.categories where name = 'Дом и сад' and parent_id is null and not exists (select 1 from public.categories where name = 'Бытовая техника') limit 1;
insert into public.categories (name, parent_id) select 'Сад и огород', id from public.categories where name = 'Дом и сад' and parent_id is null and not exists (select 1 from public.categories where name = 'Сад и огород') limit 1;
insert into public.categories (name, parent_id) select 'Интерьер и декор', id from public.categories where name = 'Дом и сад' and parent_id is null and not exists (select 1 from public.categories where name = 'Интерьер и декор') limit 1;

insert into public.categories (name, parent_id) select 'Спорт и отдых', id from public.categories where name = 'Хобби и отдых' and parent_id is null and not exists (select 1 from public.categories where name = 'Спорт и отдых') limit 1;
insert into public.categories (name, parent_id) select 'Книги', id from public.categories where name = 'Хобби и отдых' and parent_id is null and not exists (select 1 from public.categories where name = 'Книги') limit 1;
insert into public.categories (name, parent_id) select 'Музыкальные инструменты', id from public.categories where name = 'Хобби и отдых' and parent_id is null and not exists (select 1 from public.categories where name = 'Музыкальные инструменты') limit 1;
insert into public.categories (name, parent_id) select 'Коллекционирование', id from public.categories where name = 'Хобби и отдых' and parent_id is null and not exists (select 1 from public.categories where name = 'Коллекционирование') limit 1;

insert into public.categories (name, parent_id) select 'Ремонт и строительство', id from public.categories where name = 'Услуги' and parent_id is null and not exists (select 1 from public.categories where name = 'Ремонт и строительство') limit 1;
insert into public.categories (name, parent_id) select 'Курсы и обучение', id from public.categories where name = 'Услуги' and parent_id is null and not exists (select 1 from public.categories where name = 'Курсы и обучение') limit 1;
insert into public.categories (name, parent_id) select 'Красота и здоровье', id from public.categories where name = 'Услуги' and parent_id is null and not exists (select 1 from public.categories where name = 'Красота и здоровье') limit 1;
insert into public.categories (name, parent_id) select 'Транспортные услуги', id from public.categories where name = 'Услуги' and parent_id is null and not exists (select 1 from public.categories where name = 'Транспортные услуги') limit 1;

insert into public.categories (name, parent_id) select 'Вакансии', id from public.categories where name = 'Работа' and parent_id is null and not exists (select 1 from public.categories where name = 'Вакансии') limit 1;
insert into public.categories (name, parent_id) select 'Резюме', id from public.categories where name = 'Работа' and parent_id is null and not exists (select 1 from public.categories where name = 'Резюме') limit 1;

insert into public.categories (name, parent_id) select 'Собаки', id from public.categories where name = 'Животные' and parent_id is null and not exists (select 1 from public.categories where name = 'Собаки') limit 1;
insert into public.categories (name, parent_id) select 'Кошки', id from public.categories where name = 'Животные' and parent_id is null and not exists (select 1 from public.categories where name = 'Кошки') limit 1;
insert into public.categories (name, parent_id) select 'Аквариумные животные', id from public.categories where name = 'Животные' and parent_id is null and not exists (select 1 from public.categories where name = 'Аквариумные животные') limit 1;
insert into public.categories (name, parent_id) select 'Птицы', id from public.categories where name = 'Животные' and parent_id is null and not exists (select 1 from public.categories where name = 'Птицы') limit 1;

insert into public.categories (name, parent_id) select 'Игрушки', id from public.categories where name = 'Для детей' and parent_id is null and not exists (select 1 from public.categories where name = 'Игрушки') limit 1;
insert into public.categories (name, parent_id) select 'Детская одежда', c.id from public.categories c where c.name = 'Для детей' and c.parent_id is null and not exists (select 1 from public.categories c2 where c2.name = 'Детская одежда' and c2.parent_id = c.id) limit 1;
insert into public.categories (name, parent_id) select 'Коляски', id from public.categories where name = 'Для детей' and parent_id is null and not exists (select 1 from public.categories where name = 'Коляски') limit 1;
insert into public.categories (name, parent_id) select 'Детская мебель', id from public.categories where name = 'Для детей' and parent_id is null and not exists (select 1 from public.categories where name = 'Детская мебель') limit 1;

-- ============== PRODUCTS (marketplace feed) ==============
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  price decimal(12,2) not null,
  image_url text default '',
  category text default 'general',
  category_id uuid references public.categories(id) on delete set null,
  seller_id uuid not null references public.users(id) on delete cascade,
  likes_count int default 0,
  comments_count int default 0,
  created_at timestamptz default now()
);
-- Если таблица уже была без category / category_id / comments_count — добавить колонки
alter table public.products add column if not exists category text default 'general';
alter table public.products add column if not exists category_id uuid references public.categories(id) on delete set null;
alter table public.products add column if not exists comments_count int default 0;
alter table public.products add column if not exists city text;
alter table public.products add column if not exists condition text default 'any';
alter table public.products add column if not exists is_urgent boolean default false;
alter table public.products add column if not exists is_top boolean default false;
alter table public.products add column if not exists latitude double precision;
alter table public.products add column if not exists longitude double precision;
alter table public.products add column if not exists contact_phone text;
alter table public.products add column if not exists is_negotiable boolean default false;
alter table public.products add column if not exists is_giveaway boolean default false;
-- Массив URL фото (обложка дублируется в image_url для совместимости).
alter table public.products add column if not exists image_urls jsonb default '[]'::jsonb;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'products_condition_allowed'
      and conrelid = 'public.products'::regclass
  ) then
    alter table public.products
      add constraint products_condition_allowed
      check (condition in ('any', 'new', 'used'));
  end if;
end $$;

-- ============== PRODUCT LIKES ==============
create table if not exists public.product_likes (
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (product_id, user_id)
);

-- ============== PRODUCT COMMENTS ==============
create table if not exists public.product_comments (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  text text not null,
  created_at timestamptz default now()
);

-- ============== FOLLOWERS ==============
-- Пересоздаём таблицу, если она была со старой структурой (без follower_id)
drop trigger if exists on_follower_change on public.followers;
drop policy if exists "Followers select" on public.followers;
drop policy if exists "Followers all" on public.followers;
drop table if exists public.followers cascade;

create table public.followers (
  id uuid primary key default gen_random_uuid(),
  follower_id uuid not null references public.users(id) on delete cascade,
  following_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  unique(follower_id, following_id)
);

-- ============== STORIES (24h) ==============
create table if not exists public.stories (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  image_url text not null default '',
  video_url text default '',
  caption text default '',
  original_post_id uuid references public.posts(id) on delete set null,
  original_post_author_id uuid references public.users(id) on delete set null,
  original_post_author_name text default '',
  original_post_preview_url text default '',
  created_at timestamptz default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);
alter table public.stories add column if not exists caption text default '';
alter table public.stories add column if not exists original_post_id uuid references public.posts(id) on delete set null;
alter table public.stories add column if not exists original_post_author_id uuid references public.users(id) on delete set null;
alter table public.stories add column if not exists original_post_author_name text default '';
alter table public.stories add column if not exists original_post_preview_url text default '';

-- Ответы на сторис (как в Instagram)
create table if not exists public.story_replies (
  id uuid primary key default gen_random_uuid(),
  story_id uuid not null references public.stories(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  text text not null,
  created_at timestamptz default now()
);

create table if not exists public.story_views (
  story_id uuid not null references public.stories(id) on delete cascade,
  viewer_id uuid not null references public.users(id) on delete cascade,
  viewed_at timestamptz default now(),
  primary key (story_id, viewer_id)
);

-- ============== POSTS (новости, в стиле Threads — жители Темиртау) ==============
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  kind text not null default 'news',
  image_url text default '',
  video_url text default '',
  video_duration_seconds int default 0,
  caption text default '',
  likes_count int default 0,
  comments_count int default 0,
  dislikes_count int default 0,
  reposts_count int default 0,
  created_at timestamptz default now()
);
-- Если таблица posts уже была без comments_count / dislikes_count / reposts_count
alter table public.posts add column if not exists kind text not null default 'news';
alter table public.posts add column if not exists comments_count int default 0;
alter table public.posts add column if not exists dislikes_count int default 0;
alter table public.posts add column if not exists reposts_count int default 0;
alter table public.posts add column if not exists image_urls jsonb default '[]'::jsonb;

-- Нормализация старых данных:
-- всё, что не `news` и не `publication`, считаем публикацией
-- (чтобы не смешивать с разделом новостей).
update public.posts
set kind = 'publication'
where kind is null
   or btrim(kind) = ''
   or lower(kind) not in ('news', 'publication');

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'posts_kind_allowed_values'
  ) then
    alter table public.posts
      add constraint posts_kind_allowed_values
      check (kind in ('news', 'publication'));
  end if;
end $$;

-- Автонормализация kind при insert/update постов.
create or replace function public.normalize_post_kind()
returns trigger
language plpgsql
as $$
begin
  if lower(trim(coalesce(new.kind, ''))) = 'news' then
    new.kind := 'news';
  else
    new.kind := 'publication';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_normalize_post_kind on public.posts;
create trigger trg_normalize_post_kind
before insert or update on public.posts
for each row execute procedure public.normalize_post_kind();

-- Индексы для быстрых выборок публикаций/новостей и профиля.
create index if not exists idx_posts_kind_created_at
  on public.posts (kind, created_at desc);
create index if not exists idx_posts_user_created_at
  on public.posts (user_id, created_at desc);

alter table public.posts add column if not exists is_anonymous boolean not null default false;
alter table public.posts add column if not exists location_label text;
alter table public.posts add column if not exists poll_question text;
alter table public.posts add column if not exists poll_options text[];
alter table public.posts add column if not exists music_title text;
alter table public.posts add column if not exists music_artist text;
alter table public.posts add column if not exists music_preview_url text;

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
  on public.post_poll_votes for select using (true);

drop policy if exists "post_poll_votes_insert" on public.post_poll_votes;
create policy "post_poll_votes_insert"
  on public.post_poll_votes for insert
  with check (auth.uid() = user_id);

drop policy if exists "post_poll_votes_update" on public.post_poll_votes;
create policy "post_poll_votes_update"
  on public.post_poll_votes for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists idx_products_created_at
  on public.products (created_at desc);
create index if not exists idx_products_city
  on public.products (city);
create index if not exists idx_products_condition
  on public.products (condition);
create index if not exists idx_products_price
  on public.products (price);
create index if not exists idx_products_is_urgent
  on public.products (is_urgent);
create index if not exists idx_products_is_top
  on public.products (is_top);
create index if not exists idx_products_latitude
  on public.products (latitude);
create index if not exists idx_products_longitude
  on public.products (longitude);
create index if not exists idx_story_views_viewer
  on public.story_views (viewer_id);
create index if not exists idx_story_views_story
  on public.story_views (story_id);

create table if not exists public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

create table if not exists public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  parent_id uuid references public.post_comments(id) on delete cascade,
  text text not null,
  created_at timestamptz default now()
);
alter table public.post_comments add column if not exists parent_id uuid references public.post_comments(id) on delete cascade;

create table if not exists public.post_dislikes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

create table if not exists public.reposts (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

create table if not exists public.post_saves (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (post_id, user_id)
);

-- ============== NOTIFICATIONS ==============
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  type text not null,
  title text,
  body text,
  product_id uuid references public.products(id) on delete set null,
  post_id uuid references public.posts(id) on delete set null,
  story_id uuid references public.stories(id) on delete set null,
  comment_id uuid,
  read_at timestamptz,
  created_at timestamptz default now()
);
-- Уже созданная таблица без post_id / comment_id
alter table public.notifications
  add column if not exists post_id uuid references public.posts(id) on delete set null;
alter table public.notifications
  add column if not exists story_id uuid references public.stories(id) on delete set null;
alter table public.notifications add column if not exists comment_id uuid;

-- ============== REPORTS (универсальные жалобы) ==============
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

-- ============== COMMENT LIKES ==============
create table if not exists public.post_comment_likes (
  comment_id uuid not null references public.post_comments(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (comment_id, user_id)
);
create table if not exists public.product_comment_likes (
  comment_id uuid not null references public.product_comments(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (comment_id, user_id)
);

-- ============== FAVORITES ==============
create table if not exists public.favorites (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz default now(),
  unique(user_id, product_id)
);

-- ============== ORDERS (optional) ==============
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.users(id) on delete cascade,
  seller_id uuid references public.users(id) on delete set null,
  product_id uuid not null references public.products(id) on delete cascade,
  product_title text default '',
  safe_purchase boolean not null default false,
  amount_kzt numeric(12,2) default 0,
  commission_percent int not null default 4,
  commission_kzt numeric(12,2) not null default 0,
  seller_amount_kzt numeric(12,2) not null default 0,
  status text default 'pending_seller',
  seller_accepted_at timestamptz,
  buyer_confirmed_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

alter table public.orders add column if not exists seller_id uuid references public.users(id) on delete set null;
alter table public.orders add column if not exists product_title text default '';
alter table public.orders add column if not exists safe_purchase boolean not null default false;
alter table public.orders add column if not exists amount_kzt numeric(12,2) default 0;
alter table public.orders add column if not exists commission_percent int not null default 4;
alter table public.orders add column if not exists commission_kzt numeric(12,2) not null default 0;
alter table public.orders add column if not exists seller_amount_kzt numeric(12,2) not null default 0;
alter table public.orders add column if not exists seller_accepted_at timestamptz;
alter table public.orders add column if not exists buyer_confirmed_at timestamptz;
alter table public.orders add column if not exists completed_at timestamptz;
alter table public.orders add column if not exists cancelled_at timestamptz;
alter table public.orders add column if not exists updated_at timestamptz default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'orders_status_allowed_values'
      and conrelid = 'public.orders'::regclass
  ) then
    alter table public.orders
      add constraint orders_status_allowed_values
      check (status in ('pending_seller', 'in_escrow', 'completed', 'cancelled'));
  end if;
end $$;

create index if not exists idx_orders_buyer_created_at
  on public.orders (buyer_id, created_at desc);
create index if not exists idx_orders_seller_created_at
  on public.orders (seller_id, created_at desc);

-- ============== RLS ==============
alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.product_likes enable row level security;
alter table public.product_comments enable row level security;
alter table public.followers enable row level security;
alter table public.stories enable row level security;
alter table public.story_replies enable row level security;
alter table public.story_views enable row level security;
alter table public.notifications enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_dislikes enable row level security;
alter table public.reposts enable row level security;
alter table public.post_saves enable row level security;
alter table public.favorites enable row level security;
alter table public.orders enable row level security;
alter table public.post_comment_likes enable row level security;
alter table public.product_comment_likes enable row level security;

-- Удаляем политики, если уже есть (чтобы можно было перезапускать скрипт)
drop policy if exists "Posts select" on public.posts;
drop policy if exists "Posts insert" on public.posts;
drop policy if exists "Posts update own" on public.posts;
drop policy if exists "Posts delete own" on public.posts;
drop policy if exists "Post likes select" on public.post_likes;
drop policy if exists "Post likes all" on public.post_likes;
drop policy if exists "Post comments select" on public.post_comments;
drop policy if exists "Post comments insert" on public.post_comments;
drop policy if exists "Post comments delete own" on public.post_comments;
drop policy if exists "Post dislikes select" on public.post_dislikes;
drop policy if exists "Post dislikes all" on public.post_dislikes;
drop policy if exists "Reposts select" on public.reposts;
drop policy if exists "Reposts all" on public.reposts;
drop policy if exists "Post saves select" on public.post_saves;
drop policy if exists "Post saves all" on public.post_saves;

create policy "Posts select" on public.posts for select using (true);
create policy "Posts insert" on public.posts for insert with check (auth.uid() = user_id);
create policy "Posts update own" on public.posts for update using (auth.uid() = user_id);
create policy "Posts delete own" on public.posts for delete using (auth.uid() = user_id);

create policy "Post likes select" on public.post_likes for select using (true);
create policy "Post likes all" on public.post_likes for all using (auth.uid() = user_id);

create policy "Post comments select" on public.post_comments for select using (true);
create policy "Post comments insert" on public.post_comments for insert with check (auth.uid() = user_id);
create policy "Post comments delete own" on public.post_comments for delete using (auth.uid() = user_id);

drop policy if exists "Post comment likes select" on public.post_comment_likes;
drop policy if exists "Post comment likes all" on public.post_comment_likes;
create policy "Post comment likes select" on public.post_comment_likes for select using (true);
create policy "Post comment likes all" on public.post_comment_likes for all using (auth.uid() = user_id);

drop policy if exists "Product comment likes select" on public.product_comment_likes;
drop policy if exists "Product comment likes all" on public.product_comment_likes;
create policy "Product comment likes select" on public.product_comment_likes for select using (true);
create policy "Product comment likes all" on public.product_comment_likes for all using (auth.uid() = user_id);

create policy "Post dislikes select" on public.post_dislikes for select using (true);
create policy "Post dislikes all" on public.post_dislikes for all using (auth.uid() = user_id);

create policy "Reposts select" on public.reposts for select using (true);
create policy "Reposts all" on public.reposts for all using (auth.uid() = user_id);
create policy "Post saves select" on public.post_saves for select using (auth.uid() = user_id);
create policy "Post saves all" on public.post_saves for all using (auth.uid() = user_id);

drop policy if exists "Users select" on public.users;
drop policy if exists "Users update own" on public.users;
drop policy if exists "Users insert own" on public.users;
create policy "Users select" on public.users for select using (true);
create policy "Users update own"
  on public.users
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);
create policy "Users insert own" on public.users for insert with check (auth.uid() = id);

drop policy if exists "Products select" on public.products;
drop policy if exists "Products insert" on public.products;
drop policy if exists "Products update own" on public.products;
drop policy if exists "Products delete own" on public.products;
drop policy if exists "Product likes select" on public.product_likes;
drop policy if exists "Product likes all" on public.product_likes;
drop policy if exists "Product comments select" on public.product_comments;
drop policy if exists "Product comments insert" on public.product_comments;
drop policy if exists "Product comments delete own" on public.product_comments;

create policy "Products select" on public.products for select using (true);
create policy "Products insert" on public.products for insert with check (auth.uid() = seller_id);
create policy "Products update own" on public.products for update using (auth.uid() = seller_id);
create policy "Products delete own" on public.products for delete using (auth.uid() = seller_id);

create policy "Product likes select" on public.product_likes for select using (true);
create policy "Product likes all" on public.product_likes for all using (auth.uid() = user_id);

create policy "Product comments select" on public.product_comments for select using (true);
create policy "Product comments insert" on public.product_comments for insert with check (auth.uid() = user_id);
create policy "Product comments delete own" on public.product_comments for delete using (auth.uid() = user_id);

drop policy if exists "Followers select" on public.followers;
drop policy if exists "Followers all" on public.followers;
create policy "Followers select" on public.followers for select using (true);
create policy "Followers all" on public.followers for all using (auth.uid() = follower_id);

drop policy if exists "Stories select" on public.stories;
drop policy if exists "Stories insert" on public.stories;
drop policy if exists "Stories update own" on public.stories;
drop policy if exists "Stories delete own" on public.stories;
create policy "Stories select" on public.stories for select using (true);
create policy "Stories insert" on public.stories for insert with check (auth.uid() = user_id);
create policy "Stories update own" on public.stories for update using (auth.uid() = user_id);
create policy "Stories delete own" on public.stories for delete using (auth.uid() = user_id);

drop policy if exists "Story replies select" on public.story_replies;
drop policy if exists "Story replies insert" on public.story_replies;
drop policy if exists "Story replies delete own" on public.story_replies;
drop policy if exists "Story views select own" on public.story_views;
drop policy if exists "Story views select story owner" on public.story_views;
drop policy if exists "Story views insert own" on public.story_views;
drop policy if exists "Story views update own" on public.story_views;
create policy "Story replies select" on public.story_replies for select using (true);
create policy "Story replies insert" on public.story_replies for insert with check (auth.uid() = user_id);
create policy "Story replies delete own" on public.story_replies for delete using (auth.uid() = user_id);

create policy "Story views select own" on public.story_views for select using (auth.uid() = viewer_id);
create policy "Story views select story owner"
  on public.story_views for select
  using (
    exists (
      select 1
      from public.stories s
      where s.id = story_views.story_id
        and s.user_id = auth.uid()
    )
  );
create policy "Story views insert own" on public.story_views for insert with check (auth.uid() = viewer_id);
create policy "Story views update own" on public.story_views for update using (auth.uid() = viewer_id) with check (auth.uid() = viewer_id);

drop policy if exists "Notifications select" on public.notifications;
drop policy if exists "Notifications update own" on public.notifications;
create policy "Notifications select" on public.notifications for select using (auth.uid() = user_id);
create policy "Notifications update own" on public.notifications for update using (auth.uid() = user_id);
-- Вставка из клиента: автор действия (лайк/коммент/репост) записывает уведомление получателю.
drop policy if exists "Notifications insert as actor" on public.notifications;
create policy "Notifications insert as actor" on public.notifications
  for insert with check (auth.uid() = actor_id);

-- Счётчики для нижней панели: публикации/товары vs новости (см. миграцию).
create or replace function public.notification_feed_unread_counts(p_user_id uuid)
returns table (publications_count bigint, news_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select
    (
      select count(*)::bigint
      from public.notifications n
      left join public.posts p on p.id = n.post_id
      where n.user_id = p_user_id
        and n.read_at is null
        and (
          n.product_id is not null
          or (
            n.post_id is not null
            and coalesce(p.kind, 'publication') = 'publication'
          )
        )
    ) as publications_count,
    (
      select count(*)::bigint
      from public.notifications n
      inner join public.posts p on p.id = n.post_id
      where n.user_id = p_user_id
        and n.read_at is null
        and p.kind = 'news'
    ) as news_count;
$$;

revoke all on function public.notification_feed_unread_counts(uuid) from public;
grant execute on function public.notification_feed_unread_counts(uuid) to authenticated;

drop policy if exists "Favorites all" on public.favorites;
drop policy if exists "Orders all" on public.orders;
create policy "Favorites all" on public.favorites for all using (auth.uid() = user_id);
drop policy if exists "Orders select participants" on public.orders;
drop policy if exists "Orders insert buyer" on public.orders;
drop policy if exists "Orders update participants" on public.orders;
drop policy if exists "Orders delete buyer" on public.orders;
create policy "Orders select participants"
  on public.orders for select
  using (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "Orders insert buyer"
  on public.orders for insert
  with check (auth.uid() = buyer_id);
create policy "Orders update participants"
  on public.orders for update
  using (auth.uid() = buyer_id or auth.uid() = seller_id)
  with check (auth.uid() = buyer_id or auth.uid() = seller_id);
create policy "Orders delete buyer"
  on public.orders for delete
  using (auth.uid() = buyer_id);

-- ============== TRIGGERS: counts ==============
create or replace function public.update_product_likes_count()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.products set likes_count = likes_count + 1 where id = new.product_id;
  elsif tg_op = 'DELETE' then
    update public.products set likes_count = greatest(0, likes_count - 1) where id = old.product_id;
  end if;
  return null;
end;
$$ language plpgsql security definer;

create or replace function public.update_product_comments_count()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.products set comments_count = comments_count + 1 where id = new.product_id;
  elsif tg_op = 'DELETE' then
    update public.products set comments_count = greatest(0, comments_count - 1) where id = old.product_id;
  end if;
  return null;
end;
$$ language plpgsql security definer;

create or replace function public.update_followers_count()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.users set followers_count = followers_count + 1 where id = new.following_id;
    update public.users set following_count = following_count + 1 where id = new.follower_id;
  elsif tg_op = 'DELETE' then
    update public.users set followers_count = greatest(0, followers_count - 1) where id = old.following_id;
    update public.users set following_count = greatest(0, following_count - 1) where id = old.follower_id;
  end if;
  return null;
end;
$$ language plpgsql security definer;

drop trigger if exists on_product_like on public.product_likes;
create trigger on_product_like after insert or delete on public.product_likes for each row execute procedure public.update_product_likes_count();
drop trigger if exists on_product_comment on public.product_comments;
create trigger on_product_comment after insert or delete on public.product_comments for each row execute procedure public.update_product_comments_count();
drop trigger if exists on_follower_change on public.followers;
create trigger on_follower_change after insert or delete on public.followers for each row execute procedure public.update_followers_count();

-- ============== TRIGGERS: post likes/comments count ==============
create or replace function public.update_post_likes_count()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set likes_count = likes_count + 1 where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts set likes_count = greatest(0, likes_count - 1) where id = old.post_id;
  end if;
  return null;
end;
$$ language plpgsql security definer;

create or replace function public.update_post_comments_count()
returns trigger as $$
begin
  if tg_op = 'INSERT' then
    update public.posts set comments_count = comments_count + 1 where id = new.post_id;
  elsif tg_op = 'DELETE' then
    update public.posts set comments_count = greatest(0, comments_count - 1) where id = old.post_id;
  end if;
  return null;
end;
$$ language plpgsql security definer;

drop trigger if exists on_post_like on public.post_likes;
create trigger on_post_like after insert or delete on public.post_likes for each row execute procedure public.update_post_likes_count();
drop trigger if exists on_post_comment on public.post_comments;
create trigger on_post_comment after insert or delete on public.post_comments for each row execute procedure public.update_post_comments_count();

create or replace function public.apply_post_like_delta_to_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author_id uuid;
begin
  if tg_op = 'INSERT' then
    select user_id into author_id from public.posts where id = new.post_id;
    if author_id is not null then
      update public.users
      set total_received_post_likes = total_received_post_likes + 1
      where id = author_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    select user_id into author_id from public.posts where id = old.post_id;
    if author_id is not null then
      update public.users
      set total_received_post_likes = greatest(0, total_received_post_likes - 1)
      where id = author_id;
    end if;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_post_like_total_received on public.post_likes;
create trigger trg_post_like_total_received
  after insert or delete on public.post_likes
  for each row execute procedure public.apply_post_like_delta_to_author();

-- ============== Create profile on signup ==============
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text;
begin
  v_name := coalesce(
    nullif(trim(new.raw_user_meta_data->>'full_name'), ''),
    nullif(trim(new.raw_user_meta_data->>'name'), ''),
    nullif(trim(new.raw_user_meta_data->>'given_name'), ''),
    nullif(trim(new.email), ''),
    'Пользователь'
  );
  insert into public.users (id, name)
  values (new.id, v_name)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============== STORAGE BUCKETS (products, posts, stories) ==============
-- Создаёт бакеты, если их ещё нет. При повторном запуске — обновляет public.
insert into storage.buckets (id, name, public)
values
  ('products', 'products', true),
  ('posts', 'posts', true),
  ('stories', 'stories', true),
  ('avatars', 'avatars', true),
  ('messages', 'messages', true)
on conflict (id) do update set name = excluded.name, public = excluded.public;

-- Политики Storage: загрузка для авторизованных, чтение для всех
drop policy if exists "Allow authenticated uploads to products" on storage.objects;
drop policy if exists "Allow public read products" on storage.objects;
create policy "Allow authenticated uploads to products" on storage.objects for insert to authenticated with check (bucket_id = 'products');
create policy "Allow public read products" on storage.objects for select to public using (bucket_id = 'products');

drop policy if exists "Allow authenticated uploads to posts" on storage.objects;
drop policy if exists "Allow public read posts" on storage.objects;
create policy "Allow authenticated uploads to posts" on storage.objects for insert to authenticated with check (bucket_id = 'posts');
create policy "Allow public read posts" on storage.objects for select to public using (bucket_id = 'posts');

drop policy if exists "Allow authenticated uploads to stories" on storage.objects;
drop policy if exists "Allow public read stories" on storage.objects;
create policy "Allow authenticated uploads to stories" on storage.objects for insert to authenticated with check (bucket_id = 'stories');
create policy "Allow public read stories" on storage.objects for select to public using (bucket_id = 'stories');

drop policy if exists "Allow authenticated uploads to avatars" on storage.objects;
drop policy if exists "Allow public read avatars" on storage.objects;
create policy "Allow authenticated uploads to avatars" on storage.objects for insert to authenticated with check (bucket_id = 'avatars');
create policy "Allow public read avatars" on storage.objects for select to public using (bucket_id = 'avatars');

drop policy if exists "Allow authenticated uploads to messages" on storage.objects;
drop policy if exists "Allow public read messages" on storage.objects;
create policy "Allow authenticated uploads to messages" on storage.objects for insert to authenticated with check (bucket_id = 'messages');
create policy "Allow public read messages" on storage.objects for select to public using (bucket_id = 'messages');

-- ============== Delete expired stories (run via cron or Edge Function) ==============
-- delete from public.stories where expires_at < now();

-- ============== SETTINGS (privacy, notifications, security) ==============

-- User settings (single row per user)
create table if not exists public.user_settings (
  user_id uuid primary key references public.users(id) on delete cascade,
  push_notifications_enabled boolean not null default true,
  email_notifications_enabled boolean not null default true,
  in_app_notifications_enabled boolean not null default true,
  activity_status_enabled boolean not null default true,
  story_visibility text not null default 'followers',
  post_visibility text not null default 'followers',
  two_factor_enabled boolean not null default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.user_settings enable row level security;
drop policy if exists "User settings select own" on public.user_settings;
drop policy if exists "User settings insert own" on public.user_settings;
drop policy if exists "User settings update own" on public.user_settings;

create policy "User settings select own"
  on public.user_settings for select
  using (auth.uid() = user_id);

create policy "User settings insert own"
  on public.user_settings for insert
  with check (auth.uid() = user_id);

create policy "User settings update own"
  on public.user_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);


-- Blocked users list
create table if not exists public.blocked_users (
  blocker_id uuid not null references public.users(id) on delete cascade,
  blocked_user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (blocker_id, blocked_user_id)
);

alter table public.blocked_users enable row level security;
drop policy if exists "Blocked users select own" on public.blocked_users;
drop policy if exists "Blocked users insert own" on public.blocked_users;
drop policy if exists "Blocked users delete own" on public.blocked_users;

create policy "Blocked users select own"
  on public.blocked_users for select
  using (auth.uid() = blocker_id);

create policy "Blocked users insert own"
  on public.blocked_users for insert
  with check (auth.uid() = blocker_id);

create policy "Blocked users delete own"
  on public.blocked_users for delete
  using (auth.uid() = blocker_id);


-- Users hidden from my stories
create table if not exists public.hidden_stories (
  owner_id uuid not null references public.users(id) on delete cascade,
  hidden_user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (owner_id, hidden_user_id)
);

alter table public.hidden_stories enable row level security;
drop policy if exists "Hidden stories select own" on public.hidden_stories;
drop policy if exists "Hidden stories insert own" on public.hidden_stories;
drop policy if exists "Hidden stories delete own" on public.hidden_stories;
drop policy if exists "Hidden stories select for hidden user" on public.hidden_stories;

create policy "Hidden stories select own"
  on public.hidden_stories for select
  using (auth.uid() = owner_id);

create policy "Hidden stories select for hidden user"
  on public.hidden_stories for select
  using (auth.uid() = hidden_user_id);

create policy "Hidden stories insert own"
  on public.hidden_stories for insert
  with check (auth.uid() = owner_id);

create policy "Hidden stories delete own"
  on public.hidden_stories for delete
  using (auth.uid() = owner_id);


-- Group chats
create table if not exists public.chat_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  description text default '',
  is_official_city_chat boolean not null default false,
  is_discoverable boolean not null default true,
  avatar_url text default '',
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

alter table public.chat_groups add column if not exists is_discoverable boolean not null default true;

create table if not exists public.chat_group_members (
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz default now(),
  primary key (group_id, user_id)
);

create table if not exists public.chat_group_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.chat_groups(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  text text not null,
  message_type text not null default 'text',
  audio_url text,
  video_url text,
  duration_seconds int,
  city_thread text not null default 'discussion',
  created_at timestamptz default now()
);

alter table public.chat_group_messages
  add column if not exists city_thread text not null default 'discussion';
alter table public.chat_group_messages
  add column if not exists message_type text not null default 'text';
alter table public.chat_group_messages
  add column if not exists audio_url text;
alter table public.chat_group_messages
  add column if not exists video_url text;
alter table public.chat_group_messages
  add column if not exists duration_seconds int;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_group_messages_city_thread_allowed'
      and conrelid = 'public.chat_group_messages'::regclass
  ) then
    alter table public.chat_group_messages
      add constraint chat_group_messages_city_thread_allowed
      check (
        city_thread in (
          'real_estate',
          'services',
          'jobs',
          'purchases',
          'sales',
          'dating',
          'discussion'
        )
      );
  end if;
end $$;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_group_messages_message_type_allowed'
      and conrelid = 'public.chat_group_messages'::regclass
  ) then
    alter table public.chat_group_messages
      add constraint chat_group_messages_message_type_allowed
      check (message_type in ('text', 'audio', 'video_circle'));
  end if;
end $$;

alter table public.chat_groups enable row level security;
alter table public.chat_group_members enable row level security;
alter table public.chat_group_messages enable row level security;

drop policy if exists "Chat groups select members" on public.chat_groups;
drop policy if exists "Chat groups insert own" on public.chat_groups;
drop policy if exists "Chat groups update owner" on public.chat_groups;
drop policy if exists "Chat groups delete owner" on public.chat_groups;
drop policy if exists "Chat group members select own groups" on public.chat_group_members;
drop policy if exists "Chat group members insert by owner" on public.chat_group_members;
drop policy if exists "Chat group members delete by owner_or_self" on public.chat_group_members;
drop policy if exists "Chat group messages select by member" on public.chat_group_messages;
drop policy if exists "Chat group messages insert by member" on public.chat_group_messages;

create or replace function public.is_group_member(_group_id uuid, _user_id uuid)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.chat_group_members m
    where m.group_id = _group_id
      and m.user_id = _user_id
  );
$$;

revoke all on function public.is_group_member(uuid, uuid) from public;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;

create policy "Chat groups select members"
  on public.chat_groups for select
  using (
    owner_id = auth.uid()
    or public.is_group_member(id, auth.uid())
  );

-- Официальный городской чат: виден всем авторизованным (иначе новые пользователи не находят группу по названию).
create policy "Chat groups select official city all authed"
  on public.chat_groups
  for select
  to authenticated
  using (
    coalesce(is_official_city_chat, false) = true
    or trim(title) = 'Temirtau city'
  );

drop policy if exists "Chat groups select discoverable" on public.chat_groups;
create policy "Chat groups select discoverable"
  on public.chat_groups
  for select
  to authenticated
  using (coalesce(is_discoverable, false) = true);

create policy "Chat groups insert own"
  on public.chat_groups for insert
  with check (auth.uid() = owner_id);

create policy "Chat groups update owner"
  on public.chat_groups for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Chat groups delete owner"
  on public.chat_groups for delete
  using (auth.uid() = owner_id);

create or replace function public.lock_official_city_group_metadata()
returns trigger
language plpgsql
as $$
begin
  if coalesce(old.is_official_city_chat, false) then
    new.title := old.title;
    new.description := old.description;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lock_official_city_group_metadata on public.chat_groups;
create trigger trg_lock_official_city_group_metadata
  before update on public.chat_groups
  for each row
  execute procedure public.lock_official_city_group_metadata();

create policy "Chat group members select own groups"
  on public.chat_group_members for select
  using (
    public.is_group_member(group_id, auth.uid())
    or exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and g.owner_id = auth.uid()
    )
  );

create policy "Chat group members insert by owner"
  on public.chat_group_members for insert
  with check (
    exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and g.owner_id = auth.uid()
    )
  );

create policy "Chat group members insert city_member_invite"
  on public.chat_group_members for insert
  with check (
    exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and coalesce(g.is_official_city_chat, false) = true
        and public.is_group_member(g.id, auth.uid())
    )
  );

create policy "Chat group members insert self official city"
  on public.chat_group_members
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and (
          coalesce(g.is_official_city_chat, false) = true
          or trim(g.title) = 'Temirtau city'
        )
    )
  );

create policy "Chat group members delete by owner_or_self"
  on public.chat_group_members for delete
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.chat_groups g
      where g.id = chat_group_members.group_id
        and g.owner_id = auth.uid()
    )
  );

create policy "Chat group messages select by member"
  on public.chat_group_messages for select
  using (public.is_group_member(group_id, auth.uid()));

create policy "Chat group messages insert by member"
  on public.chat_group_messages for insert
  with check (
    auth.uid() = sender_id
    and public.is_group_member(group_id, auth.uid())
  );

-- Автомодерация официального городского чата (функции и триггер — см. migrations/20260330220000_city_chat_auto_moderation.sql).
create table if not exists public.city_chat_user_moderation (
  user_id uuid primary key references public.users(id) on delete cascade,
  violation_count int not null default 0,
  banned_until timestamptz,
  permanent_ban boolean not null default false,
  updated_at timestamptz not null default now()
);

alter table public.city_chat_user_moderation enable row level security;

create policy "City chat moderation select own"
  on public.city_chat_user_moderation for select
  using (auth.uid() = user_id);

-- Personal channels
create table if not exists public.user_channels (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references public.users(id) on delete cascade,
  title text not null default 'Мой канал',
  description text,
  avatar_url text,
  sign_posts boolean not null default true,
  show_link_preview boolean not null default true,
  silent_broadcast boolean not null default false,
  created_at timestamptz default now()
);

create table if not exists public.channel_messages (
  id uuid primary key default gen_random_uuid(),
  channel_id uuid not null references public.user_channels(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  text text not null,
  created_at timestamptz default now()
);

alter table public.user_channels enable row level security;
alter table public.channel_messages enable row level security;

drop policy if exists "User channels select all" on public.user_channels;
drop policy if exists "User channels insert own" on public.user_channels;
drop policy if exists "User channels update own" on public.user_channels;
drop policy if exists "User channels delete own" on public.user_channels;
drop policy if exists "Channel messages select all" on public.channel_messages;
drop policy if exists "Channel messages insert owner" on public.channel_messages;

create policy "User channels select all"
  on public.user_channels for select
  using (true);

create policy "User channels insert own"
  on public.user_channels for insert
  with check (auth.uid() = owner_id);

create policy "User channels update own"
  on public.user_channels for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "User channels delete own"
  on public.user_channels for delete
  using (auth.uid() = owner_id);

create policy "Channel messages select all"
  on public.channel_messages for select
  using (
    exists (
      select 1 from public.user_channels c
      where c.id = channel_messages.channel_id
    )
  );

create policy "Channel messages insert owner"
  on public.channel_messages for insert
  with check (
    auth.uid() = sender_id
    and exists (
      select 1 from public.user_channels c
      where c.id = channel_messages.channel_id
        and c.owner_id = auth.uid()
    )
  );


-- Support tickets ("Report a problem")
create table if not exists public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  description text not null,
  created_at timestamptz default now()
);

alter table public.support_tickets enable row level security;
drop policy if exists "Support tickets select own" on public.support_tickets;
drop policy if exists "Support tickets insert own" on public.support_tickets;

create policy "Support tickets select own"
  on public.support_tickets for select
  using (auth.uid() = user_id);

create policy "Support tickets insert own"
  on public.support_tickets for insert
  with check (auth.uid() = user_id);


-- Login history (optional, used by UI in this feature)
create table if not exists public.login_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  logged_in_at timestamptz default now(),
  ip_address text,
  user_agent text
);

alter table public.login_history enable row level security;
drop policy if exists "Login history select own" on public.login_history;
drop policy if exists "Login history delete own" on public.login_history;

create policy "Login history select own"
  on public.login_history for select
  using (auth.uid() = user_id);

create policy "Login history delete own"
  on public.login_history for delete
  using (auth.uid() = user_id);


-- Stored session records (optional, used for "session management" screen)
create table if not exists public.user_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  created_at timestamptz default now(),
  last_seen_at timestamptz default now(),
  device text,
  ip_address text
);

alter table public.user_sessions enable row level security;
drop policy if exists "User sessions select own" on public.user_sessions;
drop policy if exists "User sessions delete own" on public.user_sessions;

create policy "User sessions select own"
  on public.user_sessions for select
  using (auth.uid() = user_id);

create policy "User sessions delete own"
  on public.user_sessions for delete
  using (auth.uid() = user_id);


-- ============== ПЕРСОНАЛЬНЫЕ РЕКОМЕНДАЦИИ (просмотры публикаций в ленте) ==============
-- Накопленное время просмотра по (user, post) для скоринга авторов/интересов.
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

-- Нужно для RPC increment_publication_feed_impression (insert + upsert).
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

-- Атомарное увеличение watched_ms (клиент не шлёт полный upsert).
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

-- Reels: порядок видео-публикаций по сессии (см. migrations/20260406210000_reels_video_post_ids.sql).
create or replace function public.reels_video_post_ids(
  p_limit integer,
  p_offset integer,
  p_session_key text
)
returns uuid[]
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    array(
      select p.id
      from public.posts p
      where p.kind = 'publication'
        and p.video_url is not null
        and btrim(p.video_url) <> ''
      order by md5(
        p.id::text || coalesce(nullif(trim(p_session_key), ''), 'tmr-reels-default')
      )
      limit greatest(1, least(coalesce(p_limit, 20), 50))
      offset greatest(0, coalesce(p_offset, 0))
    ),
    '{}'::uuid[]
  );
$$;

grant execute on function public.reels_video_post_ids(integer, integer, text) to anon, authenticated;

-- ============== Личные сообщения (direct messages) ==============
-- Базовая таблица и RLS: migrations/20250314000000_messages_rls_delete.sql
-- Расширения: migrations/20260403190000_dm_read_receipts_presence_reactions.sql

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.users(id) on delete cascade,
  receiver_id uuid not null references public.users(id) on delete cascade,
  text text not null default '',
  created_at timestamptz default now()
);

alter table public.messages add column if not exists message_type text not null default 'text';
alter table public.messages add column if not exists audio_url text;
alter table public.messages add column if not exists video_url text;
alter table public.messages add column if not exists duration_seconds int not null default 0;
alter table public.messages add column if not exists read_at timestamptz;
alter table public.messages add column if not exists forward_of uuid references public.messages(id) on delete set null;
alter table public.messages add column if not exists image_url text;
alter table public.messages add column if not exists file_url text;
alter table public.messages add column if not exists file_name text;
alter table public.messages add column if not exists reply_to uuid references public.messages (id) on delete set null;

create index if not exists idx_messages_reply_to on public.messages (reply_to)
  where reply_to is not null;

alter table public.messages drop constraint if exists messages_message_type_check;
alter table public.messages drop constraint if exists messages_message_type_allowed;

alter table public.messages
  add constraint messages_message_type_allowed
  check (
    message_type in (
      'text',
      'audio',
      'video_circle',
      'image',
      'gif',
      'sticker',
      'file',
      'event',
      'location'
    )
  );

create index if not exists idx_messages_dm_unread
  on public.messages (receiver_id, sender_id)
  where read_at is null;

create table if not exists public.message_reactions (
  message_id uuid not null references public.messages(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (message_id, user_id),
  constraint message_reactions_emoji_len check (
    char_length(emoji) >= 1 and char_length(emoji) <= 64
  )
);

create index if not exists idx_message_reactions_message_id
  on public.message_reactions (message_id);

alter table public.messages enable row level security;
drop policy if exists "Messages select own" on public.messages;
create policy "Messages select own" on public.messages
  for select using (auth.uid() = sender_id or auth.uid() = receiver_id);
drop policy if exists "Messages insert own" on public.messages;
create policy "Messages insert own" on public.messages
  for insert with check (auth.uid() = sender_id);
drop policy if exists "Messages delete own" on public.messages;
create policy "Messages delete own" on public.messages
  for delete using (auth.uid() = sender_id or auth.uid() = receiver_id);

alter table public.message_reactions enable row level security;
drop policy if exists "message_reactions select thread" on public.message_reactions;
create policy "message_reactions select thread"
  on public.message_reactions for select using (
    exists (
      select 1
      from public.messages m
      where m.id = message_id
        and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())
    )
  );
drop policy if exists "message_reactions insert thread" on public.message_reactions;
create policy "message_reactions insert thread"
  on public.message_reactions for insert with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.messages m
      where m.id = message_id
        and (m.sender_id = auth.uid() or m.receiver_id = auth.uid())
    )
  );
drop policy if exists "message_reactions update own" on public.message_reactions;
create policy "message_reactions update own"
  on public.message_reactions for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
drop policy if exists "message_reactions delete own" on public.message_reactions;
create policy "message_reactions delete own"
  on public.message_reactions for delete using (auth.uid() = user_id);

grant select, insert, update, delete on public.message_reactions to authenticated;

drop function if exists public.mark_dm_messages_read(uuid);
create or replace function public.mark_dm_messages_read(p_peer_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  update public.messages
  set read_at = now()
  where receiver_id = auth.uid()
    and sender_id = p_peer_id
    and read_at is null;
end;
$$;
grant execute on function public.mark_dm_messages_read(uuid) to authenticated;

-- ============== Заметка к сторис (RLS, не users.story_note) ==============
-- См. migrations/20260327140000_user_story_settings.sql
create table if not exists public.user_story_settings (
  user_id uuid primary key references public.users(id) on delete cascade,
  story_note text not null default '',
  note_location text not null default '',
  share_location boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.user_story_settings enable row level security;
drop policy if exists "user_story_settings_select_allowed" on public.user_story_settings;
drop policy if exists "user_story_settings_insert_own" on public.user_story_settings;
drop policy if exists "user_story_settings_update_own" on public.user_story_settings;
drop policy if exists "user_story_settings_delete_own" on public.user_story_settings;
create policy "user_story_settings_select_allowed"
  on public.user_story_settings for select
  using (
    auth.uid() = user_id
    or exists (
      select 1
      from public.followers f
      where f.follower_id = auth.uid()
        and f.following_id = user_story_settings.user_id
    )
    or exists (
      select 1
      from public.messages m
      where (m.sender_id = auth.uid() and m.receiver_id = user_story_settings.user_id)
         or (m.receiver_id = auth.uid() and m.sender_id = user_story_settings.user_id)
    )
    or exists (
      select 1
      from public.chat_group_members m1
      join public.chat_group_members m2 on m1.group_id = m2.group_id
      where m1.user_id = auth.uid()
        and m2.user_id = user_story_settings.user_id
        and m1.user_id <> m2.user_id
    )
  );
create policy "user_story_settings_insert_own"
  on public.user_story_settings for insert
  with check (auth.uid() = user_id);
create policy "user_story_settings_update_own"
  on public.user_story_settings for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "user_story_settings_delete_own"
  on public.user_story_settings for delete
  using (auth.uid() = user_id);
grant select, insert, update, delete on public.user_story_settings to authenticated;

-- ============== Платное продвижение товаров (см. migrations/20250322140000_product_promotions.sql) ==============
-- Колонки: promo_top_until, promo_urgent_until, promo_highlight_until, stats_access_until, view_count;
-- Таблица: product_promotion_orders; RPC: increment_product_view.

create or replace function public.spend_qarmet_and_apply_product_promotion(
  p_product_id uuid,
  p_kind text,
  p_cost int default 1,
  p_duration_hours int default 24
)
returns void
language plpgsql
security invoker
set search_path = public
as $$
declare
  v_uid uuid;
  v_balance int;
  v_now timestamptz;
  v_top_base timestamptz;
  v_urgent_base timestamptz;
  v_highlight_base timestamptz;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Пользователь не авторизован';
  end if;

  if p_cost <= 0 then
    raise exception 'Стоимость продвижения должна быть больше 0';
  end if;
  if p_duration_hours <= 0 then
    raise exception 'Длительность продвижения должна быть больше 0';
  end if;
  if p_kind not in ('top', 'urgent', 'highlight', 'all_in_one') then
    raise exception 'Неизвестный тип продвижения: %', p_kind;
  end if;

  perform 1
  from public.products p
  where p.id = p_product_id
    and p.seller_id = v_uid
  for update;

  if not found then
    raise exception 'Продвижение доступно только владельцу товара';
  end if;

  select u.qarmet_balance
    into v_balance
  from public.users u
  where u.id = v_uid
  for update;

  if v_balance is null then
    raise exception 'Профиль пользователя не найден';
  end if;

  if v_balance < p_cost then
    raise exception 'Недостаточно Qarmet. Нужно: %, доступно: %', p_cost, v_balance;
  end if;

  update public.users
  set qarmet_balance = v_balance - p_cost
  where id = v_uid;

  v_now := now();

  if p_kind = 'top' then
    select case
      when p.promo_top_until is not null and p.promo_top_until > v_now
        then p.promo_top_until
      else v_now
    end
    into v_top_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_top = true,
        promo_top_until = v_top_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  elsif p_kind = 'urgent' then
    select case
      when p.promo_urgent_until is not null and p.promo_urgent_until > v_now
        then p.promo_urgent_until
      else v_now
    end
    into v_urgent_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_urgent = true,
        promo_urgent_until = v_urgent_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  elsif p_kind = 'highlight' then
    select case
      when p.promo_highlight_until is not null and p.promo_highlight_until > v_now
        then p.promo_highlight_until
      else v_now
    end
    into v_highlight_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set promo_highlight_until = v_highlight_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;

  else
    select
      case
        when p.promo_top_until is not null and p.promo_top_until > v_now
          then p.promo_top_until
        else v_now
      end,
      case
        when p.promo_urgent_until is not null and p.promo_urgent_until > v_now
          then p.promo_urgent_until
        else v_now
      end,
      case
        when p.promo_highlight_until is not null and p.promo_highlight_until > v_now
          then p.promo_highlight_until
        else v_now
      end
    into v_top_base, v_urgent_base, v_highlight_base
    from public.products p
    where p.id = p_product_id;

    update public.products
    set is_top = true,
        is_urgent = true,
        promo_top_until = v_top_base + make_interval(hours => p_duration_hours),
        promo_urgent_until = v_urgent_base + make_interval(hours => p_duration_hours),
        promo_highlight_until = v_highlight_base + make_interval(hours => p_duration_hours)
    where id = p_product_id;
  end if;
end;
$$;

revoke all on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) from public;
grant execute on function public.spend_qarmet_and_apply_product_promotion(uuid, text, int, int) to authenticated;

create table if not exists public.gift_catalog (
  id text primary key,
  name text not null,
  price int not null check (price > 0),
  animation text not null default 'default'
);

create table if not exists public.live_battles (
  id uuid primary key default gen_random_uuid(),
  host_a uuid not null references public.users(id) on delete cascade,
  host_b uuid not null references public.users(id) on delete cascade,
  score_a int not null default 0 check (score_a >= 0),
  score_b int not null default 0 check (score_b >= 0),
  end_time timestamptz not null,
  is_active boolean not null default true,
  winner_id uuid references public.users(id) on delete set null,
  mvp_sender_id uuid references public.users(id) on delete set null,
  top3_donators jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.live_battle_events (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null references public.live_battles(id) on delete cascade,
  sender_id uuid not null references public.users(id) on delete cascade,
  target_host uuid not null references public.users(id) on delete cascade,
  event_type text not null check (event_type in ('like', 'gift')),
  gift_id text references public.gift_catalog(id) on delete set null,
  gift_price int not null default 0 check (gift_price >= 0),
  points_awarded int not null default 0 check (points_awarded >= 0),
  created_at timestamptz not null default now()
);

create index if not exists idx_live_battle_events_battle_created
  on public.live_battle_events (battle_id, created_at desc);

create table if not exists public.live_battle_results (
  id uuid primary key default gen_random_uuid(),
  battle_id uuid not null unique references public.live_battles(id) on delete cascade,
  host_a uuid not null references public.users(id) on delete cascade,
  host_b uuid not null references public.users(id) on delete cascade,
  winner_id uuid references public.users(id) on delete set null,
  score_a int not null default 0,
  score_b int not null default 0,
  mvp_sender_id uuid references public.users(id) on delete set null,
  top3_donators jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.live_rooms (
  id uuid primary key default gen_random_uuid(),
  host_id uuid not null references public.users(id) on delete cascade,
  title text not null default '',
  is_live boolean not null default true,
  created_at timestamptz not null default now(),
  ended_at timestamptz
);

create index if not exists idx_live_rooms_live_created
  on public.live_rooms (is_live, created_at desc);

-- FCM push tokens (миграция 20260406200000_user_push_tokens.sql; RLS: только свои строки).
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

