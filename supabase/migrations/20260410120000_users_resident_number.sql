-- Номер жителя города (отображается в профиле; ввод при регистрации / в настройках).
alter table public.users add column if not exists resident_number text;

comment on column public.users.resident_number is
  'Номер жителя (муниципальный/городской идентификатор), опционально';
