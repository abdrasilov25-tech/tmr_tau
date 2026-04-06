-- Reels: стабильный «случайный» порядок видео-публикаций для сессии (ключ → md5).
-- Удалённые из БД посты автоматически отсутствуют в выборке.

create or replace function public.reels_video_post_ids(
  p_limit integer,
  p_offset integer,
  p_session_key text
)
returns uuid[]
language sql
stable
security invoker
set search_path = public
as $$
  select coalesce(
    array(
      select p.id
      from public.posts p
      where p.kind = 'publication'
        and p.video_url is not null
        and btrim(p.video_url) <> ''
      order by md5(
        p.id::text || coalesce(nullif(trim(p_session_key), ''), 'tmr-reels-default')
      )
      limit greatest(1, least(coalesce(p_limit, 20), 50))
      offset greatest(0, coalesce(p_offset, 0))
    ),
    '{}'::uuid[]
  );
$$;

grant execute on function public.reels_video_post_ids(integer, integer, text) to anon, authenticated;
