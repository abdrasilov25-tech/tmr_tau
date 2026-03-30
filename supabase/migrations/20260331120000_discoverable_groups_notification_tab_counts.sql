-- Глобальный поиск групп по названию (как публичные в Telegram): все авторизованные
-- видят метаданные групп с is_discoverable = true (по умолчанию true для существующих и новых).
alter table public.chat_groups
  add column if not exists is_discoverable boolean not null default true;

comment on column public.chat_groups.is_discoverable is
  'Публичный поиск по названию: при false группа видна только участникам и владельцу (кроме официального городского).';

drop policy if exists "Chat groups select discoverable" on public.chat_groups;

create policy "Chat groups select discoverable"
  on public.chat_groups
  for select
  to authenticated
  using (coalesce(is_discoverable, false) = true);

-- Счётчики непрочитанных для вкладок «Публикации» и «Новости» (разделение по kind поста).
create or replace function public.notification_feed_unread_counts(p_user_id uuid)
returns table (publications_count bigint, news_count bigint)
language sql
stable
security invoker
set search_path = public
as $$
  select
    (
      select count(*)::bigint
      from public.notifications n
      left join public.posts p on p.id = n.post_id
      where n.user_id = p_user_id
        and n.read_at is null
        and (
          n.product_id is not null
          or (
            n.post_id is not null
            and coalesce(p.kind, 'publication') = 'publication'
          )
        )
    ) as publications_count,
    (
      select count(*)::bigint
      from public.notifications n
      inner join public.posts p on p.id = n.post_id
      where n.user_id = p_user_id
        and n.read_at is null
        and p.kind = 'news'
    ) as news_count;
$$;

revoke all on function public.notification_feed_unread_counts(uuid) from public;
grant execute on function public.notification_feed_unread_counts(uuid) to authenticated;
