alter table public.posts add column if not exists latitude double precision;
alter table public.posts add column if not exists longitude double precision;
alter table public.posts add column if not exists is_promoted boolean not null default false;
alter table public.posts add column if not exists promoted_until timestamptz;

create index if not exists idx_posts_geo_lat on public.posts (latitude);
create index if not exists idx_posts_geo_lng on public.posts (longitude);
create index if not exists idx_posts_promoted_until on public.posts (is_promoted, promoted_until desc);

alter table public.users add column if not exists premium_active boolean not null default false;
alter table public.users add column if not exists premium_until timestamptz;

create index if not exists idx_users_premium_until on public.users (premium_active, premium_until desc);
