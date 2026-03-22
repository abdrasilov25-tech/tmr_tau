# Edge Functions: оплата продвижения объявлений (KZ)

**Пошаговая инструкция (CLI, Stripe, webhook):** см. [`docs/PAYMENT_SETUP.md`](../../docs/PAYMENT_SETUP.md).

---

## Безопасность

- **Секреты** `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `SUPABASE_SERVICE_ROLE_KEY` задаются в **Supabase Dashboard → Edge Functions → Secrets**, не в Flutter и не в git.
- Приложение вызывает только `create-product-promotion` с JWT пользователя; деньги и обновление строк в БД — на сервере.

## Stripe (рекомендуется для старта)

1. Создайте продукт в [Stripe](https://stripe.com) (тестовый режим).
2. Разверните функции:
   - `supabase functions deploy create-product-promotion`
   - `supabase functions deploy stripe-webhook`
3. В Stripe Dashboard → Webhooks добавьте URL вида  
   `https://<project>.supabase.co/functions/v1/stripe-webhook`  
   и событие `checkout.session.completed`.
4. Скопируйте **Signing secret** в `STRIPE_WEBHOOK_SECRET`.

## Halyk / Caspipay (Казахстан)

Подключение банковских эквайрингов делается **на сервере**: отдельная Edge Function или backend, который:

1. Принимает `product_id` и `kind` (как в `create-product-promotion`).
2. Создаёт заказ в `product_promotion_orders` со `status: pending`.
3. Вызывает API Halyk/Caspipay и возвращает клиенту `checkout_url` для `url_launcher`.
4. По callback/webhook банка обновляет заказ и поля `promo_*_until` в `products` (аналогично `stripe-webhook`).

Не храните merchant keys в мобильном приложении.

## Переменные

| Переменная | Назначение |
|------------|------------|
| `PUBLIC_APP_URL` | Редирект после оплаты (можно deep link приложения). |
| `STRIPE_SECRET_KEY` | Секрет Stripe. |
| `STRIPE_WEBHOOK_SECRET` | Подпись webhook. |

_(Триггер CI: push в `main` с изменениями в `supabase/functions/` запускает деплой.)_
