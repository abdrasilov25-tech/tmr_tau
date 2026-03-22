#!/usr/bin/env bash
# Деплой Edge Functions для оплаты (Stripe).
# Локально: Supabase CLI + `supabase login` и `supabase link`, либо переменные:
#   export SUPABASE_ACCESS_TOKEN=...
#   export SUPABASE_PROJECT_REF=abcdefgh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REF_ARGS=()
if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
  REF_ARGS=(--project-ref "$SUPABASE_PROJECT_REF")
fi

echo "==> Deploy create-product-promotion"
supabase functions deploy create-product-promotion "${REF_ARGS[@]}"

echo "==> Deploy stripe-webhook (JWT отключён в supabase/config.toml)"
supabase functions deploy stripe-webhook "${REF_ARGS[@]}"

echo "Готово."
echo "Секреты Stripe: Supabase Dashboard → Edge Functions → Secrets, или:"
echo "  supabase secrets set STRIPE_SECRET_KEY=sk_test_... ${REF_ARGS[*]}"
echo "Полный чеклист: docs/PAYMENT_SETUP.md и .github/SECRETS.md"
