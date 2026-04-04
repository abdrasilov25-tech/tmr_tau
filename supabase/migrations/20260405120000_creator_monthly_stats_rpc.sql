-- Статистика создателя за 30 дней (подписка Official Page): просмотры ленты, взаимодействия, подписчики, посты.
-- Доступна только при users.official_page_active = true.

create or replace function public.get_creator_monthly_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_since timestamptz := (now() at time zone 'utc') - interval '30 days';
  v_official boolean;
  v_views bigint;
  v_likes bigint;
  v_comments bigint;
  v_reposts bigint;
  v_new_followers bigint;
  v_posts bigint;
begin
  if v_uid is null then
    raise exception 'unauthorized';
  end if;

  select coalesce(u.official_page_active, false)
  into v_official
  from public.users u
  where u.id = v_uid;

  if not coalesce(v_official, false) then
    return jsonb_build_object(
      'eligible', false,
      'period_days', 30
    );
  end if;

  -- Просмотры: накопленные показы постов автора в ленте (строки impressions).
  select coalesce(count(*), 0) into v_views
  from public.publication_feed_impressions pfi
  inner join public.posts p on p.id = pfi.post_id
  where p.user_id = v_uid
    and pfi.last_seen_at >= v_since;

  select coalesce(count(*), 0) into v_likes
  from public.post_likes pl
  inner join public.posts p on p.id = pl.post_id
  where p.user_id = v_uid
    and pl.created_at >= v_since;

  select coalesce(count(*), 0) into v_comments
  from public.post_comments pc
  inner join public.posts p on p.id = pc.post_id
  where p.user_id = v_uid
    and pc.created_at >= v_since
    and pc.parent_id is null;

  select coalesce(count(*), 0) into v_reposts
  from public.reposts r
  inner join public.posts p on p.id = r.post_id
  where p.user_id = v_uid
    and r.created_at >= v_since;

  select coalesce(count(*), 0) into v_new_followers
  from public.followers f
  where f.following_id = v_uid
    and f.created_at >= v_since;

  select coalesce(count(*), 0) into v_posts
  from public.posts p
  where p.user_id = v_uid
    and p.created_at >= v_since;

  return jsonb_build_object(
    'eligible', true,
    'period_days', 30,
    'profile_views', v_views,
    'interactions', v_likes + v_comments + v_reposts,
    'new_followers', v_new_followers,
    'shared_posts', v_posts
  );
end;
$$;

revoke all on function public.get_creator_monthly_stats() from public;
grant execute on function public.get_creator_monthly_stats() to authenticated;

create index if not exists idx_publication_feed_impressions_post_seen
  on public.publication_feed_impressions (post_id, last_seen_at desc);
