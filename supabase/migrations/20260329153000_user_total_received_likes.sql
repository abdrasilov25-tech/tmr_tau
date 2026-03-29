-- Суммарные лайки по всем постам автора (как в TikTok): актуально при лайках и удалении постов.
alter table public.users
  add column if not exists total_received_post_likes int not null default 0;

update public.users u
set total_received_post_likes = coalesce((
  select sum(p.likes_count)::int
  from public.posts p
  where p.user_id = u.id
), 0);

create or replace function public.apply_post_like_delta_to_author()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  author_id uuid;
begin
  if tg_op = 'INSERT' then
    select user_id into author_id from public.posts where id = new.post_id;
    if author_id is not null then
      update public.users
      set total_received_post_likes = total_received_post_likes + 1
      where id = author_id;
    end if;
    return new;
  elsif tg_op = 'DELETE' then
    select user_id into author_id from public.posts where id = old.post_id;
    if author_id is not null then
      update public.users
      set total_received_post_likes = greatest(0, total_received_post_likes - 1)
      where id = author_id;
    end if;
    return old;
  end if;
  return null;
end;
$$;

drop trigger if exists trg_post_like_total_received on public.post_likes;
create trigger trg_post_like_total_received
  after insert or delete on public.post_likes
  for each row execute procedure public.apply_post_like_delta_to_author();
