# Полный чеклист tmrtau App (одним проходом)

Автоматически из кода выполнить **нельзя**: Supabase, Stripe и магазины требуют входа **в твой аккаунт**. Этот файл — **единая инструкция** по порядку.

---

## 0. Уже сделано в проекте (код)

- Edge Functions: `create-product-promotion`, `stripe-webhook`
- Flutter: монетизация, лендинг в `site/`, GitHub Pages workflow
- CI: `.github/workflows/deploy-supabase-functions.yml` (деплой функций + опциональная синхронизация секретов)

---

## 1. База данных (Supabase → SQL Editor)

Один раз выполни миграцию продвижения (если ещё не делал):

- Файл: `supabase/migrations/20250322140000_product_promotions.sql`  
  или готовый блок из переписки / `docs/PAYMENT_SETUP.md` (раздел SQL).

Проверка: в **Table Editor** есть `product_promotion_orders`, у `products` — колонки `promo_*`, `view_count`.

---

## 2. Секреты Stripe (вручную в Dashboard)

**Test mode** в Stripe:

1. **Developers → API keys** — Secret key `sk_test_...`
2. **Developers → Webhooks** — Webhook (destination), URL:
   ```text
   https://mukxbmcrwxqfbuhxoltd.supabase.co/functions/v1/stripe-webhook
   ```
   Событие: **`checkout.session.completed`** → Signing secret `whsec_...`

Подставь свой **Project ref**, если проект другой.

---

## 3. Секреты Supabase Edge Functions

**Dashboard → Edge Functions → Secrets** (или CLI `supabase secrets set`):

| Name | Значение |
|------|----------|
| `STRIPE_SECRET_KEY` | `sk_test_...` |
| `STRIPE_WEBHOOK_SECRET` | `whsec_...` |
| `PUBLIC_APP_URL` | `https://abdrasilov25-tech.github.io/tmr_tau/` |

`SUPABASE_URL` / ключи обычно подставляются сами; если в логах функции «missing secrets» — см. **Settings → API**.

---

## 4. Синхронизация через GitHub (вместо ручного ввода в п.3)

В **GitHub → Settings → Secrets → Actions** задай:

- `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF` (обязательно)
- `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `PUBLIC_APP_URL` (как в таблице выше)

Запусти workflow **Deploy Supabase Edge Functions** (**Actions → Run workflow**).  
Шаг **Sync payment secrets** выполнит `supabase secrets set` за тебя (см. `.github/workflows/deploy-supabase-functions.yml`).

---

## 5. Деплой функций

- Либо workflow из п.4, либо локально: `./scripts/deploy-edge-functions.sh`
- В **Supabase → Edge Functions** должны быть `create-product-promotion` и `stripe-webhook`.

---

## 6. Сайт (политика / Stripe business URL)

- Лендинг: `site/` → GitHub Pages (см. `docs/GITHUB_PAGES.md`)
- В приложении URL политики: `lib/.../privacy_policy_page.dart` — уже на GitHub Pages

---

## 7. Проверка в приложении

1. Выйди и войди снова (сессия JWT).
2. Свой товар → продвижение → тестовая карта `4242 4242 4242 4242`.
3. Stripe: webhook **200**; таблица `product_promotion_orders` → `paid`.

Ошибка **401 Invalid JWT** — см. обновление сессии в `ProductMonetizationRepositoryImpl`; при необходимости пересобери приложение.

---

## 8. Сборка Android

```bash
flutter pub get
flutter build apk --release
# или для Google Play:
flutter build appbundle --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

---

## 9. Продакшен (позже)

- Stripe **Live**: новые `sk_live_...`, отдельный webhook в Live → новый `whsec_...` → обновить секреты Supabase/GitHub.
- Google Play / App Store: консоли разработчика, подпись, скриншоты, политика конфиденциальности (URL с п.6).

---

## Быстрая навигация по документам

| Тема | Файл |
|------|------|
| Оплата Stripe + CLI | `docs/PAYMENT_SETUP.md` |
| Секреты GitHub Actions | `.github/SECRETS.md` |
| GitHub Pages | `docs/GITHUB_PAGES.md` |
