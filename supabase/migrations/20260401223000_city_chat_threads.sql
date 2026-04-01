-- Split official city chat into semantic threads.

alter table public.chat_group_messages
  add column if not exists city_thread text not null default 'general';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'chat_group_messages_city_thread_allowed'
      and conrelid = 'public.chat_group_messages'::regclass
  ) then
    alter table public.chat_group_messages
      add constraint chat_group_messages_city_thread_allowed
      check (
        city_thread in ('general', 'roads', 'checks', 'market', 'help')
      );
  end if;
end $$;

create index if not exists idx_chat_group_messages_group_thread_created
  on public.chat_group_messages (group_id, city_thread, created_at);

-- Backfill existing official city chat messages to the default thread.
update public.chat_group_messages m
set city_thread = 'general'
from public.chat_groups g
where g.id = m.group_id
  and (coalesce(g.is_official_city_chat, false) = true or trim(g.title) = 'Temirtau city')
  and (m.city_thread is null or trim(m.city_thread) = '');
