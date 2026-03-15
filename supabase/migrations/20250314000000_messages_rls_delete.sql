-- Таблица сообщений для чатов (если ещё не создана) и политики RLS, в т.ч. на удаление.
-- Выполни в Supabase → SQL Editor, если «Удалить чат» выдаёт ошибку.

-- Таблица (пропусти, если уже есть)
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.users(id) on delete cascade,
  receiver_id uuid not null references public.users(id) on delete cascade,
  text text not null default '',
  created_at timestamptz default now()
);

alter table public.messages enable row level security;

-- Читать: только свои диалоги (отправитель или получатель — я)
drop policy if exists "Messages select own" on public.messages;
create policy "Messages select own" on public.messages
  for select using (
    auth.uid() = sender_id or auth.uid() = receiver_id
  );

-- Писать: только от своего имени
drop policy if exists "Messages insert own" on public.messages;
create policy "Messages insert own" on public.messages
  for insert with check (auth.uid() = sender_id);

-- Удалять: только сообщения, где я участник (отправитель или получатель)
drop policy if exists "Messages delete own" on public.messages;
create policy "Messages delete own" on public.messages
  for delete using (
    auth.uid() = sender_id or auth.uid() = receiver_id
  );

-- RPC: удалить всю переписку с пользователем. Возвращает {} — иначе клиент Supabase падает на void.
drop function if exists public.delete_chat(uuid);
create or replace function public.delete_chat(peer_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $body$
begin
  delete from public.messages
  where (sender_id = auth.uid() and receiver_id = peer_id)
     or (sender_id = peer_id and receiver_id = auth.uid());
  return '{}'::json;
end;
$body$;

-- Разрешить вызов любому авторизованному пользователю
grant execute on function public.delete_chat(uuid) to authenticated;
grant execute on function public.delete_chat(uuid) to service_role;
