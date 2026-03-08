-- tmr_tau — Marketplace + Social (Instagram/TikTok style)
-- Run in Supabase SQL Editor after creating a project

-- ============== USERS (profiles) ==============
create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text,
  avatar text,
  bio text,
  followers_count int default 0,
  following_count int default 0,
  is_verified boolean default false,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

-- If table already exists, add column: alter table public.users add column if not exists is_verified boolean default false;

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
-- Если таблица уже была без category / category_id — добавить колонки
alter table public.products add column if not exists category text default 'general';
alter table public.products add column if not exists category_id uuid references public.categories(id) on delete set null;

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
  created_at timestamptz default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

-- ============== POSTS (новости, в стиле Threads — жители Темиртау) ==============
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
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
  text text not null,
  created_at timestamptz default now()
);

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

-- ============== NOTIFICATIONS ==============
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  actor_id uuid references public.users(id) on delete set null,
  type text not null,
  title text,
  body text,
  product_id uuid references public.products(id) on delete set null,
  read_at timestamptz,
  created_at timestamptz default now()
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
  product_id uuid not null references public.products(id) on delete cascade,
  status text default 'pending',
  created_at timestamptz default now()
);

-- ============== RLS ==============
alter table public.users enable row level security;
alter table public.products enable row level security;
alter table public.product_likes enable row level security;
alter table public.product_comments enable row level security;
alter table public.followers enable row level security;
alter table public.stories enable row level security;
alter table public.notifications enable row level security;
alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;
alter table public.post_dislikes enable row level security;
alter table public.reposts enable row level security;
alter table public.favorites enable row level security;
alter table public.orders enable row level security;

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

create policy "Posts select" on public.posts for select using (true);
create policy "Posts insert" on public.posts for insert with check (auth.uid() = user_id);
create policy "Posts update own" on public.posts for update using (auth.uid() = user_id);
create policy "Posts delete own" on public.posts for delete using (auth.uid() = user_id);

create policy "Post likes select" on public.post_likes for select using (true);
create policy "Post likes all" on public.post_likes for all using (auth.uid() = user_id);

create policy "Post comments select" on public.post_comments for select using (true);
create policy "Post comments insert" on public.post_comments for insert with check (auth.uid() = user_id);
create policy "Post comments delete own" on public.post_comments for delete using (auth.uid() = user_id);

create policy "Post dislikes select" on public.post_dislikes for select using (true);
create policy "Post dislikes all" on public.post_dislikes for all using (auth.uid() = user_id);

create policy "Reposts select" on public.reposts for select using (true);
create policy "Reposts all" on public.reposts for all using (auth.uid() = user_id);

drop policy if exists "Users select" on public.users;
drop policy if exists "Users update own" on public.users;
drop policy if exists "Users insert own" on public.users;
create policy "Users select" on public.users for select using (true);
create policy "Users update own" on public.users for update using (auth.uid() = id);
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
drop policy if exists "Stories delete own" on public.stories;
create policy "Stories select" on public.stories for select using (true);
create policy "Stories insert" on public.stories for insert with check (auth.uid() = user_id);
create policy "Stories delete own" on public.stories for delete using (auth.uid() = user_id);

drop policy if exists "Notifications select" on public.notifications;
drop policy if exists "Notifications update own" on public.notifications;
create policy "Notifications select" on public.notifications for select using (auth.uid() = user_id);
create policy "Notifications update own" on public.notifications for update using (auth.uid() = user_id);

drop policy if exists "Favorites all" on public.favorites;
drop policy if exists "Orders all" on public.orders;
create policy "Favorites all" on public.favorites for all using (auth.uid() = user_id);
create policy "Orders all" on public.orders for all using (auth.uid() = buyer_id);

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

-- ============== Create profile on signup ==============
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, name)
  values (new.id, coalesce(new.raw_user_meta_data->>'name', new.email));
  return new;
end;
$$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ============== Delete expired stories (run via cron or Edge Function) ==============
-- delete from public.stories where expires_at < now();
