-- Автомодерация официального городского чата (is_official_city_chat):
-- мат / 18+ / открытая агрессия → предупреждение → бан 3 суток → 7 суток → навсегда.
-- Проверка только для kind = 'text'. Системные и city_rules не трогаем.

create table if not exists public.city_chat_user_moderation (
  user_id uuid primary key references public.users(id) on delete cascade,
  violation_count int not null default 0,
  banned_until timestamptz,
  permanent_ban boolean not null default false,
  updated_at timestamptz not null default now()
);

comment on table public.city_chat_user_moderation is
  'Страйки автомодерации для сообщений в официальных городских групповых чатах.';

alter table public.city_chat_user_moderation enable row level security;

drop policy if exists "City chat moderation select own" on public.city_chat_user_moderation;
create policy "City chat moderation select own"
  on public.city_chat_user_moderation for select
  using (auth.uid() = user_id);

-- Нормализация: нижний регистр, ё→е, обход простых «звёздочек».
create or replace function public.city_chat_normalize_for_scan(p_raw text)
returns text
language sql
immutable
set search_path = public
as $$
  select trim(
    both ' '
    from regexp_replace(
      regexp_replace(
        lower(translate(coalesce(p_raw, ''), 'ёЁ', 'еЕ')),
        '[*_•·‧]+',
        '',
        'g'
      ),
      '\s+',
      ' ',
      'g'
    )
  );
$$;

-- Эвристика по словам и фразам (RU/EN). Расширяйте списки при необходимости.
create or replace function public.city_chat_text_is_acceptable(p_raw text)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  t text;
  padded text;
  w text;
  ph text;
  adult_phrases text[] := array[
    ' порно ', ' порнух', ' порнограф', ' эротик', ' минет ', ' простит',
    ' интим ', ' оргазм', ' мастурб', ' онаниз', ' фелляц', ' куннил',
    ' наркот', ' закладк', ' дилдо', ' фетиш', ' бдсм', ' камшот',
    ' ххх ', ' xxx ', ' porn ', ' sex ', ' nude ', ' nsfw ', ' naked '
  ];
begin
  t := city_chat_normalize_for_scan(p_raw);
  if t = '' or length(t) < 2 then
    return true;
  end if;

  padded := ' ' || t || ' ';
  if padded ~ '(^|[^0-9])18[[:space:]]*\+' or padded similar to '%ххх%' or t ~ '(^|[^a-z])xxx([^a-z]|$)' then
    return false;
  end if;

  foreach ph in array adult_phrases
  loop
    if position(ph in padded) > 0 then
      return false;
    end if;
  end loop;

  -- «секс» отдельным словом (избегаем «сексопилок» и т.п.).
  foreach w in array regexp_split_to_array(t, '[[:space:]]+')
  loop
    continue when w is null or length(w) < 3;
    if w in ('секс', 'sex', 'xxx', 'porn', 'porno', 'сука', 'суки', 'мудак', 'пидор', 'говно', 'fuck', 'shit', 'bitch', 'хуй', 'хер', 'пизда', 'блять', 'бля', 'ёб', 'ебать') then
      return false;
    end if;
  end loop;

  if t ~ '(^|[^а-яa-zё0-9])(убью|убей|убейте|убивать|зарежу|зареж|прикончу|прикончи|умри|умрите|дохни|сдохни|выпилю|выслежу|разнесу|взорву|уроню|сломаю|труп|урод)([^а-яa-zё0-9]|$)' then
    return false;
  end if;

  -- Мат и грубые оскорбления (корни между разделителями).
  if t ~ '(^|[^а-яa-zё0-9])(хуй|хуё|хуе|хуя|хуи|херни|хрен|пизд|пезд|еб[аиоуё]|ёб|ебл|ебу|ебут|ебёт|ебет|бля|бляд|суцк|срал|сру|говн|мудак|мудил|мудозв|пидор|педик|педер|гомик|гондон|шлюх|шалав|мраз|твар|чмо|лоху|лох |урод|дебил|даун|fuck|shit|bitch|cunt|dick|cock|slut)([^а-яa-zё0-9]|$)' then
    return false;
  end if;

  return true;
end;
$$;

create or replace function public.city_chat_is_post_blocked(p_user_id uuid)
returns boolean
language sql
stable
set search_path = public
as $$
  select coalesce(
    (
      select m.permanent_ban
           or (m.banned_until is not null and m.banned_until > now())
      from public.city_chat_user_moderation m
      where m.user_id = p_user_id
    ),
    false
  );
$$;

-- Увеличить счётчик нарушения и выбросить код для клиента (сообщение не вставляется).
create or replace function public.city_chat_register_violation(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count int;
begin
  insert into public.city_chat_user_moderation as m (
    user_id,
    violation_count,
    banned_until,
    permanent_ban,
    updated_at
  )
  values (p_user_id, 1, null, false, now())
  on conflict (user_id) do update
  set
    violation_count = m.violation_count + 1,
    updated_at = now()
  returning violation_count into v_count;

  if v_count = 1 then
    raise exception 'CITY_CHAT_WARNING'
      using hint = 'Первое нарушение: предупреждение. Сообщение не отправлено.';
  end if;

  if v_count = 2 then
    update public.city_chat_user_moderation
    set
      banned_until = now() + interval '3 days',
      permanent_ban = false
    where user_id = p_user_id;
    raise exception 'CITY_CHAT_BAN_3D'
      using hint = 'Повторное нарушение: запрет писать в городской чат на 3 суток.';
  end if;

  if v_count = 3 then
    update public.city_chat_user_moderation
    set
      banned_until = now() + interval '7 days',
      permanent_ban = false
    where user_id = p_user_id;
    raise exception 'CITY_CHAT_BAN_7D'
      using hint = 'Третье нарушение: запрет на 7 суток.';
  end if;

  update public.city_chat_user_moderation
  set
    permanent_ban = true,
    banned_until = null
  where user_id = p_user_id;

  raise exception 'CITY_CHAT_BAN_PERM'
    using hint = 'Четвёртое и последующие нарушения: постоянная блокировка городского чата.';
end;
$$;

create or replace function public.city_chat_enforce_group_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_official boolean;
begin
  if tg_op <> 'INSERT' then
    return new;
  end if;

  select coalesce(g.is_official_city_chat, false)
  into v_official
  from public.chat_groups g
  where g.id = new.group_id;

  if not v_official then
    return new;
  end if;

  if coalesce(new.kind, 'text') is distinct from 'text' then
    return new;
  end if;

  if public.city_chat_is_post_blocked(new.sender_id) then
    raise exception 'CITY_CHAT_BLOCKED'
      using hint = 'Вам временно или навсегда ограничена отправка сообщений в городском чате.';
  end if;

  if not public.city_chat_text_is_acceptable(new.text) then
    perform public.city_chat_register_violation(new.sender_id);
    -- register_violation всегда кидает исключение
    return null;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_city_chat_enforce_group_message on public.chat_group_messages;

create trigger trg_city_chat_enforce_group_message
  before insert on public.chat_group_messages
  for each row
  execute procedure public.city_chat_enforce_group_message();

revoke all on function public.city_chat_normalize_for_scan(text) from public;
revoke all on function public.city_chat_text_is_acceptable(text) from public;
revoke all on function public.city_chat_is_post_blocked(uuid) from public;
revoke all on function public.city_chat_register_violation(uuid) from public;
revoke all on function public.city_chat_enforce_group_message() from public;

grant execute on function public.city_chat_normalize_for_scan(text) to authenticated;
grant execute on function public.city_chat_text_is_acceptable(text) to authenticated;
grant execute on function public.city_chat_is_post_blocked(uuid) to authenticated;
