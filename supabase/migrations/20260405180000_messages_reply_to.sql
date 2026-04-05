-- Ответ на сообщение в личном чате (как в WhatsApp).

alter table public.messages
  add column if not exists reply_to uuid references public.messages (id) on delete set null;

create index if not exists idx_messages_reply_to on public.messages (reply_to)
  where reply_to is not null;
