-- Личные сообщения: URL медиа/файлов и расширенный message_type.
-- Без этого вставки с message_type image/gif и колонкой image_url падают по CHECK / отсутствию колонки.

alter table public.messages add column if not exists image_url text;
alter table public.messages add column if not exists file_url text;
alter table public.messages add column if not exists file_name text;

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
      'file',
      'event',
      'location'
    )
  );
