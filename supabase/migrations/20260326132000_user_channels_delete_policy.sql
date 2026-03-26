drop policy if exists "User channels delete own" on public.user_channels;

create policy "User channels delete own"
  on public.user_channels for delete
  using (auth.uid() = owner_id);
