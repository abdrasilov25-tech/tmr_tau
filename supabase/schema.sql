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

-- ============== PRODUCTS (marketplace feed) ==============
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  price decimal(12,2) not null,
  image_url text default '',
  category text default 'general',
  seller_id uuid not null references public.users(id) on delete cascade,
  likes_count int default 0,
  comments_count int default 0,
  created_at timestamptz default now()
);

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
create table if not exists public.followers (
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
alter table public.favorites enable row level security;
alter table public.orders enable row level security;

create policy "Users select" on public.users for select using (true);
create policy "Users update own" on public.users for update using (auth.uid() = id);
create policy "Users insert own" on public.users for insert with check (auth.uid() = id);

create policy "Products select" on public.products for select using (true);
create policy "Products insert" on public.products for insert with check (auth.uid() = seller_id);
create policy "Products update own" on public.products for update using (auth.uid() = seller_id);
create policy "Products delete own" on public.products for delete using (auth.uid() = seller_id);

create policy "Product likes select" on public.product_likes for select using (true);
create policy "Product likes all" on public.product_likes for all using (auth.uid() = user_id);

create policy "Product comments select" on public.product_comments for select using (true);
create policy "Product comments insert" on public.product_comments for insert with check (auth.uid() = user_id);
create policy "Product comments delete own" on public.product_comments for delete using (auth.uid() = user_id);

create policy "Followers select" on public.followers for select using (true);
create policy "Followers all" on public.followers for all using (auth.uid() = follower_id);

create policy "Stories select" on public.stories for select using (true);
create policy "Stories insert" on public.stories for insert with check (auth.uid() = user_id);
create policy "Stories delete own" on public.stories for delete using (auth.uid() = user_id);

create policy "Notifications select" on public.notifications for select using (auth.uid() = user_id);
create policy "Notifications update own" on public.notifications for update using (auth.uid() = user_id);

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
