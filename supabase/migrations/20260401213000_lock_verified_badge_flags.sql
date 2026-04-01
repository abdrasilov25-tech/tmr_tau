-- Prevent users from self-assigning paid official flags or verification badges.
create or replace function public.prevent_self_assign_official_or_verified_flags()
returns trigger
language plpgsql
as $$
begin
  if auth.role() = 'authenticated'
     and auth.uid() is not null
     and new.id = auth.uid()
     and (
       coalesce(new.is_verified, false) is distinct from coalesce(old.is_verified, false)
       or coalesce(new.official_page_active, false) is distinct from coalesce(old.official_page_active, false)
       or coalesce(new.official_page_profile_perks, false) is distinct from coalesce(old.official_page_profile_perks, false)
       or coalesce(new.official_page_promo_perks, false) is distinct from coalesce(old.official_page_promo_perks, false)
       or coalesce(new.official_page_last_credit_at, to_timestamp(0)) is distinct from coalesce(old.official_page_last_credit_at, to_timestamp(0))
       or coalesce(new.seller_verified_store, false) is distinct from coalesce(old.seller_verified_store, false)
       or coalesce(new.seller_plan, 'free') is distinct from coalesce(old.seller_plan, 'free')
       or coalesce(new.seller_extended_stats, false) is distinct from coalesce(old.seller_extended_stats, false)
       or coalesce(new.qarmet_balance, 0) is distinct from coalesce(old.qarmet_balance, 0)
     ) then
    raise exception 'forbidden: paid official/verification flags are managed by backend only';
  end if;

  return new;
end;
$$;

drop trigger if exists trg_prevent_self_assign_verified_badges on public.users;
create trigger trg_prevent_self_assign_verified_badges
before update on public.users
for each row
execute function public.prevent_self_assign_official_or_verified_flags();
