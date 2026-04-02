-- Личные чаты: прочитано (read_at), «онлайн» (users.last_active_at), реакции, ссылка на пересланное.
-- Клиент: chat_page.dart (галочки, статус, реакции, переслать).

alter table public.users add column if not exists last_active_at timestamptz;

alter table public.messages add column if not exists message_type text not null default 'text';
alter table public.messages add column if not exists audio_url text;
alter table public.messages add column if not exists video_url text;
alter table public.messages add column if not exists duration_seconds int not null default 0;
alter table public.messages add column if not exists read_at timestamptz;
alter table public.messages add column if not exists forward_of uuid references public.messages(id) on delete set null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'messages_message_type_allowed'
      and conrelid = 'public.messages'::regclass
  ) then
    alter table public.messages
      add constraint messages_message_type_allowed
      check (message_type in ('text', 'audio', 'video_circle'));
  end if;
end $$;

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
