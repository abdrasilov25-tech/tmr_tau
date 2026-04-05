-- DM: allow sticker messages (emoji or custom image URL).
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
