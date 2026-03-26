-- Supabase SQL Editor: поля канала + RPC приглашений (дополнение к group_channel_social).
-- Запускайте после sql_editor_group_channel_social.sql

alter table public.user_channels
  add column if not exists description text;

alter table public.user_channels
  add column if not exists avatar_url text;

alter table public.user_channels
  add column if not exists sign_posts boolean not null default true;

alter table public.user_channels
  add column if not exists show_link_preview boolean not null default true;

alter table public.user_channels
  add column if not exists silent_broadcast boolean not null default false;

create or replace function public.channel_owner_invite_users(
  p_channel_id uuid,
  p_user_ids uuid[]
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  oid uuid := auth.uid();
  invitee uuid;
  uname text;
  ids uuid[];
begin
  if oid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (
    select 1 from public.user_channels c
    where c.id = p_channel_id and c.owner_id = oid
  ) then
    raise exception 'not channel owner';
  end if;

  ids := coalesce(p_user_ids, array[]::uuid[]);
  if array_length(ids, 1) is null then
    return;
  end if;

  FOREACH invitee IN ARRAY ids
  LOOP
    if invitee is null or invitee = oid then
      continue;
    end if;
    if exists (
      select 1 from public.channel_subscribers s
      where s.channel_id = p_channel_id and s.user_id = invitee
    ) then
      continue;
    end if;

    select coalesce(nullif(trim(name), ''), 'Пользователь')
      into uname from public.users where id = invitee;

    insert into public.channel_subscribers (channel_id, user_id)
    values (p_channel_id, invitee);

    insert into public.channel_messages (channel_id, sender_id, text, kind)
    values (
      p_channel_id,
      invitee,
      coalesce(uname, 'Пользователь'),
      'system_invite'
    );
  END LOOP;
end;
$$;

revoke all on function public.channel_owner_invite_users(uuid, uuid[]) from public;
grant execute on function public.channel_owner_invite_users(uuid, uuid[]) to authenticated;
