-- Публичный бакет для медиа чатов: личные DM (префикс dm/) и группы (group_messages/).
-- Ранее код ссылался на несуществующие chat_media / messages → Storage 404.

insert into storage.buckets (id, name, public)
values ('messages', 'messages', true)
on conflict (id) do update set name = excluded.name, public = excluded.public;

drop policy if exists "Allow authenticated uploads to messages" on storage.objects;
drop policy if exists "Allow public read messages" on storage.objects;

create policy "Allow authenticated uploads to messages"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'messages');

create policy "Allow public read messages"
  on storage.objects for select to public
  using (bucket_id = 'messages');
