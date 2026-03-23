#!/usr/bin/env bash
# Деплой Edge Functions для In-App Purchase.
# Локально: Supabase CLI + `supabase login` и `supabase link`, либо переменные:
#   export SUPABASE_ACCESS_TOKEN=...
#   export SUPABASE_PROJECT_REF=abcdefgh
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v supabase >/dev/null 2>&1; then
  SUPABASE_BIN=(supabase)
else
  SUPABASE_BIN=(npx --yes supabase@latest)
fi

deploy_fn() {
  local fn_name="$1"
  echo "==> Deploy ${fn_name}"
  if [ -n "${SUPABASE_PROJECT_REF:-}" ]; then
    "${SUPABASE_BIN[@]}" functions deploy "${fn_name}" --project-ref "$SUPABASE_PROJECT_REF"
  else
    "${SUPABASE_BIN[@]}" functions deploy "${fn_name}"
  fi
}

deploy_fn "verifyPurchase"
deploy_fn "updateUserPremium"
deploy_fn "updateBoostStatus"

echo "Готово."
echo "Готово. Для server-side валидации чеков добавь секреты Apple/Google (если используешь)."
echo "Полный чеклист: docs/PAYMENT_SETUP.md и .github/SECRETS.md"
