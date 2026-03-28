-- Заметка к сторис и локация: отдельная таблица с RLS (не полагаемся на SELECT * FROM users).
-- Колонки users.story_note / note_location / share_location после бэкапа можно не трогать (совместимость со старыми клиентами).

create table if not exists public.user_story_settings (
  user_id uuid primary key references public.users(id) on delete cascade,
  story_note text not null default '',
  note_location text not null default '',
  share_location boolean not null default false,
  updated_at timestamptz not null default now()
);

create index if not exists user_story_settings_updated_at_idx
  on public.user_story_settings (updated_at desc);

alter table public.user_story_settings enable row level security;

drop policy if exists "user_story_settings_select_allowed" on public.user_story_settings;
drop policy if exists "user_story_settings_insert_own" on public.user_story_settings;
drop policy if exists "user_story_settings_update_own" on public.user_story_settings;
drop policy if exists "user_story_settings_delete_own" on public.user_story_settings;

-- Читать: свой профиль; подписок; direct-собеседников; участников общих групповых чатов.
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

insert into public.user_story_settings (user_id, story_note, note_location, share_location)
select
  u.id,
  coalesce(u.story_note, ''),
  coalesce(u.note_location, ''),
  coalesce(u.share_location, false)
from public.users u
on conflict (user_id) do update set
  story_note = excluded.story_note,
  note_location = excluded.note_location,
  share_location = excluded.share_location,
  updated_at = now();
