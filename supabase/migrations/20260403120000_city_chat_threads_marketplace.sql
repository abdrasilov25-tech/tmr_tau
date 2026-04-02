-- Городской чат: новые разделы (недвижимость, услуги, работа, …).
-- Старые значения city_thread маппятся на новые.

alter table public.chat_group_messages
  drop constraint if exists chat_group_messages_city_thread_allowed;

update public.chat_group_messages
set city_thread = case btrim(city_thread)
  when 'general' then 'discussion'
  when 'roads' then 'discussion'
  when 'checks' then 'discussion'
  when 'market' then 'sales'
  when 'help' then 'services'
  else btrim(city_thread)
end
where btrim(city_thread) in ('general', 'roads', 'checks', 'market', 'help');

update public.chat_group_messages
set city_thread = 'discussion'
where city_thread is null
   or btrim(city_thread) = ''
   or city_thread not in (
     'real_estate',
     'services',
     'jobs',
     'purchases',
     'sales',
     'dating',
     'discussion'
   );

alter table public.chat_group_messages
  alter column city_thread set default 'discussion';

alter table public.chat_group_messages
  add constraint chat_group_messages_city_thread_allowed
  check (
    city_thread in (
      'real_estate',
      'services',
      'jobs',
      'purchases',
      'sales',
      'dating',
      'discussion'
    )
  );
