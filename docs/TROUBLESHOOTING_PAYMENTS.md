# Ошибки оплаты (Stripe + Edge Functions)

## `401` / `Invalid JWT`

Не про Stripe-ключ. Шлюз Supabase не принял **JWT пользователя**.

1. Выйти из аккаунта в приложении и войти снова.
2. Проверить **`.env`**: `SUPABASE_URL` и `SUPABASE_ANON_KEY` именно **этого** проекта (Settings → API), без пробелов и кавычек.
3. Убедиться, что открыт **свой** товар (продавец = текущий пользователь).

## Ошибки с текстом `Stripe:`

Проблема на стороне **Stripe** или секрета **`STRIPE_SECRET_KEY`** в **Edge Functions → Secrets**.

1. Ключ **Test** (`sk_test_...`) при тестовой оплате; **Live** — только с боевым режимом в Stripe.
2. После смены ключа в Stripe — обновить секрет в Supabase (и в GitHub Secrets, если CI синхронизирует).
3. В Stripe для аккаунта должна быть разрешена валюта **KZT** (иначе возможны ошибки при создании Checkout).

## Webhook не обновляет заказ

1. В Supabase задан **`STRIPE_WEBHOOK_SECRET`** (тот же режим Test/Live, что и ключ).
2. URL webhook в Stripe: `https://<PROJECT_REF>.supabase.co/functions/v1/stripe-webhook`, событие **`checkout.session.completed`**.
3. Логи: **Edge Functions → stripe-webhook → Logs**.

## SQL

Таблица **`product_promotion_orders`** и колонки **`promo_*`** в **`products`** должны существовать (миграция `20250322140000_product_promotions.sql`).
