-- Media support for group/city chats: audio + round video.

alter table public.chat_group_messages
  add column if not exists message_type text not null default 'text';

alter table public.chat_group_messages
  add column if not exists audio_url text;

alter table public.chat_group_messages
  add column if not exists video_url text;

alter table public.chat_group_messages
  add column if not exists duration_seconds int;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_group_messages_message_type_allowed'
      and conrelid = 'public.chat_group_messages'::regclass
  ) then
    alter table public.chat_group_messages
      add constraint chat_group_messages_message_type_allowed
      check (message_type in ('text', 'audio', 'video_circle'));
  end if;
end $$;

create index if not exists idx_chat_group_messages_message_type
  on public.chat_group_messages (message_type);
