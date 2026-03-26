-- =============================================================================
-- Supabase SQL Editor: групповые чаты + каналы (системные сообщения, подписка)
-- Скопируйте весь файл в Dashboard → SQL Editor → Run.
-- Идемпотентно: колонки/таблица с IF NOT EXISTS, политики пересоздаются.
-- =============================================================================

-- Группы: тип сообщения (обычный / системное событие).
alter table public.chat_group_messages
  add column if not exists kind text not null default 'text';

comment on column public.chat_group_messages.kind is 'text | system_join | system_leave | system_created';

-- Каналы: тип сообщения + подписчики.
alter table public.channel_messages
  add column if not exists kind text not null default 'text';

create table if not exists public.channel_subscribers (
  channel_id uuid not null references public.user_channels(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (channel_id, user_id)
);

create index if not exists idx_channel_subscribers_user on public.channel_subscribers(user_id);

alter table public.channel_subscribers enable row level security;

drop policy if exists "Channel subscribers select" on public.channel_subscribers;
drop policy if exists "Channel subscribers insert self" on public.channel_subscribers;
drop policy if exists "Channel subscribers delete self or owner" on public.channel_subscribers;

create policy "Channel subscribers select"
  on public.channel_subscribers for select
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.user_channels c
      where c.id = channel_subscribers.channel_id
        and c.owner_id = auth.uid()
    )
  );

create policy "Channel subscribers insert self"
  on public.channel_subscribers for insert
  with check (
    auth.uid() = user_id
    and exists (select 1 from public.user_channels c where c.id = channel_subscribers.channel_id)
  );

create policy "Channel subscribers delete self or owner"
  on public.channel_subscribers for delete
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.user_channels c
      where c.id = channel_subscribers.channel_id
        and c.owner_id = auth.uid()
    )
  );

-- Сообщения канала: владелец публикует только посты kind = 'text'.
drop policy if exists "Channel messages insert owner" on public.channel_messages;

create policy "Channel messages insert owner"
  on public.channel_messages for insert
  with check (
    kind = 'text'
    and auth.uid() = sender_id
    and exists (
      select 1 from public.user_channels c
      where c.id = channel_messages.channel_id
        and c.owner_id = auth.uid()
    )
  );

-- Подписка/отписка через RPC (вставка system_* из-под security definer).
drop policy if exists "Channel messages insert subscriber system" on public.channel_messages;

create or replace function public.channel_subscribe(p_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uname text;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if exists (select 1 from public.user_channels where id = p_channel_id and owner_id = uid) then
    return;
  end if;
  if exists (select 1 from public.channel_subscribers where channel_id = p_channel_id and user_id = uid) then
    return;
  end if;
  select coalesce(nullif(trim(name), ''), 'Пользователь')
    into uname from public.users where id = uid;
  insert into public.channel_subscribers (channel_id, user_id)
  values (p_channel_id, uid);
  insert into public.channel_messages (channel_id, sender_id, text, kind)
  values (p_channel_id, uid, coalesce(uname, 'Пользователь'), 'system_subscribe');
end;
$$;

create or replace function public.channel_unsubscribe(p_channel_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uname text;
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (select 1 from public.channel_subscribers where channel_id = p_channel_id and user_id = uid) then
    return;
  end if;
  select coalesce(nullif(trim(name), ''), 'Пользователь')
    into uname from public.users where id = uid;
  insert into public.channel_messages (channel_id, sender_id, text, kind)
  values (p_channel_id, uid, coalesce(uname, 'Пользователь'), 'system_unsubscribe');
  delete from public.channel_subscribers
  where channel_id = p_channel_id and user_id = uid;
end;
$$;

revoke all on function public.channel_subscribe(uuid) from public;
revoke all on function public.channel_unsubscribe(uuid) from public;
grant execute on function public.channel_subscribe(uuid) to authenticated;
grant execute on function public.channel_unsubscribe(uuid) to authenticated;
