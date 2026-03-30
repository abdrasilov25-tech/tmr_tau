-- Официальный городской чат: фиксация названия/описания, приглашения участников любым членом.

alter table public.chat_groups
  add column if not exists is_official_city_chat boolean not null default false;

update public.chat_groups
set is_official_city_chat = true
where trim(title) = 'Temirtau city';

comment on column public.chat_groups.is_official_city_chat is
  'Официальная группа города: title/description меняются только через SQL/админку.';

-- Не давать владельцу (и никому) менять название и описание официальной группы.
create or replace function public.lock_official_city_group_metadata()
returns trigger
language plpgsql
as $$
begin
  if coalesce(old.is_official_city_chat, false) then
    new.title := old.title;
    new.description := old.description;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_lock_official_city_group_metadata on public.chat_groups;
create trigger trg_lock_official_city_group_metadata
  before update on public.chat_groups
  for each row
  execute procedure public.lock_official_city_group_metadata();

-- Любой участник официальной группы может пригласить нового члена (раньше — только owner).
drop policy if exists "Chat group members insert city_member_invite" on public.chat_group_members;

create policy "Chat group members insert city_member_invite"
  on public.chat_group_members for insert
  with check (
    exists (
      select 1
      from public.chat_groups g
      where g.id = chat_group_members.group_id
        and coalesce(g.is_official_city_chat, false) = true
        and public.is_group_member(g.id, auth.uid())
    )
  );

comment on column public.chat_group_messages.kind is
  'text | system_join | system_leave | system_created | system_removed | city_rules | …';
