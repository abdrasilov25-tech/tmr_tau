# Секреты GitHub Actions (автодеплой Edge Functions)

Создай в репозитории: **Settings → Secrets and variables → Actions → New repository secret**.

| Secret | Обязательно | Где взять |
|--------|-------------|-----------|
| `SUPABASE_ACCESS_TOKEN` | Да | [Supabase Dashboard](https://supabase.com/dashboard/account/tokens) → **Access Tokens** → Generate new token |
| `SUPABASE_PROJECT_REF` | Да | URL проекта: `https://supabase.com/dashboard/project/`**`abcdefgh`** ← это ref |
| `STRIPE_SECRET_KEY` | Нет* | Stripe → Developers → API keys → Secret key (`sk_test_...`) |
| `STRIPE_WEBHOOK_SECRET` | Нет* | После создания webhook в Stripe → Signing secret (`whsec_...`) |
| `PUBLIC_APP_URL` | Нет* | HTTPS страница после оплаты, например `https://tmr-tau.kz` |

\*Если заданы, workflow шаг **Sync payment secrets** выполнит `supabase secrets set` за тебя. Иначе задай секреты вручную: **Supabase → Edge Functions → Secrets** или локально `supabase secrets set ...`.

После пуша в `main` (или **Actions → Deploy Supabase Edge Functions → Run workflow**) функции задеплоятся сами.
