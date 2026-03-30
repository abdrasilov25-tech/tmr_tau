-- Городской чат должен быть виден и доступен ВСЕМ авторизованным пользователям:
-- раньше SELECT chat_groups был только у owner/участников → новые пользователи не видели группу
-- и не могли вступить (INSERT в members разрешён только owner / уже участнику).

-- Читать метаданные официальной городской группы (и legacy по точному названию).
drop policy if exists "Chat groups select official city all authed" on public.chat_groups;

create policy "Chat groups select official city all authed"
  on public.chat_groups
  for select
  to authenticated
  using (
    coalesce(is_official_city_chat, false) = true
    or trim(title) = 'Temirtau city'
  );

-- Самостоятельно вступить в городской чат (строка участника: user_id = auth.uid()).
drop policy if exists "Chat group members insert self official city" on public.chat_group_members;

create policy "Chat group members insert self official city"
  on public.chat_group_members
  for insert
  to authenticated
  with check (
    auth.uid() = user_id
    and exists (
      select 1
      from public.chat_groups g
      where g.id = chat_group_members.group_id
        and (
          coalesce(g.is_official_city_chat, false) = true
          or trim(g.title) = 'Temirtau city'
        )
    )
  );
