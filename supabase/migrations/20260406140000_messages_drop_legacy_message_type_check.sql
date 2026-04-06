-- Личные сообщения: в некоторых проектах CHECK на message_type создавался как
-- messages_message_type_check (автоимя), а миграции снимали только
-- messages_message_type_allowed — вставки с sticker/gif/image продолжали падать.
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

-- Входящие уведомления в приложении (Realtime INSERT для экрана «Уведомления»).
do $realtime$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $realtime$;
