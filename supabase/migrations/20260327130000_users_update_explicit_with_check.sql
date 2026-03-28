-- Явный WITH CHECK для UPDATE на users (тот же смысл, что и using, защита от смены id в одном запросе).
drop policy if exists "Users update own" on public.users;
create policy "Users update own"
  on public.users
  for update
  using (auth.uid() = id)
  with check (auth.uid() = id);
