-- Идемпотентность IAP: одна и та же покупка не должна создавать две строки payment_orders
-- при повторном вызове verifyPurchase (redelivery StoreKit, ретраи клиента).
create unique index if not exists payment_orders_user_provider_payment_uidx
  on public.payment_orders (user_id, provider_payment_id)
  where provider_payment_id is not null and btrim(provider_payment_id) <> '';
