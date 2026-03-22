# Подключение оплаты (Stripe + Supabase Edge Functions)

**Всё по шагам в одном файле:** [`docs/FULL_SETUP_CHECKLIST.md`](FULL_SETUP_CHECKLIST.md)

Код в приложении уже вызывает функцию `create-product-promotion` и опрашивает таблицу `product_promotion_orders`. Осталось привязать проект Supabase и задеплоить функции.

## Автодеплой через GitHub (рекомендуется)

1. Создай **Access Token** в [Supabase Account → Access Tokens](https://supabase.com/dashboard/account/tokens).
2. В репозитории GitHub: **Settings → Secrets → Actions** — добавь секреты из **[`.github/SECRETS.md`](../.github/SECRETS.md)** (минимум `SUPABASE_ACCESS_TOKEN` и `SUPABASE_PROJECT_REF`).
3. Запушь в `main` или открой **Actions → Deploy Supabase Edge Functions → Run workflow**.

Опционально добавь `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `PUBLIC_APP_URL` — workflow сам выполнит `supabase secrets set` при деплое.

---

## 1. Установи Supabase CLI

```bash
brew install supabase/tap/supabase
```

## 2. Войди и привяжи проект

```bash
cd /путь/к/tmr_tau
supabase login
supabase link --project-ref ТВОЙ_PROJECT_REF
```

`PROJECT_REF` — из URL: `https://supabase.com/dashboard/project/abcdefgh`.

## 3. Секреты (Stripe + URL)

В [Stripe Dashboard](https://dashboard.stripe.com) (режим **Test** для проверки):

1. **Developers → API keys** — скопируй **Secret key** (`sk_test_...`).
2. Пока не создавай webhook — URL появится после шага 4.

В терминале (или в **Supabase → Edge Functions → Manage secrets**):

```bash
supabase secrets set STRIPE_SECRET_KEY=sk_test_xxxxxxxx
supabase secrets set PUBLIC_APP_URL=https://твой-домен.kz
```

`PUBLIC_APP_URL` — страница «спасибо» после оплаты (может быть любой HTTPS; для теста подойдёт лендинг).

**Webhook secret** добавь после шага 5:

```bash
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_xxxxxxxx
```

`SUPABASE_SERVICE_ROLE_KEY` и `SUPABASE_ANON_KEY` в Edge Functions обычно **подставляются автоматически**; если в логах функции пишет «не хватает ключа», задай вручную из **Settings → API**.

## 4. Деплой функций

```bash
./scripts/deploy-edge-functions.sh
```

Или вручную:

```bash
supabase functions deploy create-product-promotion
supabase functions deploy stripe-webhook
```

`verify_jwt` для `stripe-webhook` отключён в `supabase/config.toml` (Stripe не шлёт JWT).

## 5. Webhook в Stripe

1. **Developers → Webhooks → Add endpoint**
2. URL:  
   `https://ТВОЙ_REF.supabase.co/functions/v1/stripe-webhook`
3. Событие: **`checkout.session.completed`**
4. Скопируй **Signing secret** → выполни `supabase secrets set STRIPE_WEBHOOK_SECRET=...`

## 6. SQL

Таблицы и RPC должны быть применены (миграция `20250322140000_product_promotions.sql`).

## 7. Проверка в приложении

1. Войди под продавцом.
2. Открой **свой** товар → **«Продвижение и статистика»**.
3. Выбери услугу → откроется **Stripe Checkout** (тестовая карта `4242 4242 4242 4242`).
4. После оплаты нажми **«Проверить оплату»** (webhook мог обработаться с задержкой 1–5 с).

Если видишь ошибку про Edge Function — проверь деплой и секреты в логах: **Supabase → Edge Functions → Logs**.
