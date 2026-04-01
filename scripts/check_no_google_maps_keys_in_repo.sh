#!/usr/bin/env bash
# Fail if a Google Maps/Browser-style API key pattern appears in git-tracked files.
set -euo pipefail
cd "$(dirname "$0")/.."

# 1) Block any raw Google API key-like tokens in tracked files.
if git grep -n --extended-regexp 'AIzaSy[0-9A-Za-z_-]{10,}' -- . \
  ':(exclude)docs/google-maps-release-safety.md' 2>/dev/null; then
  echo >&2 ""
  echo >&2 "ERROR: Possible Google API key (AIzaSy...) in tracked files. Remove it from git."
  exit 1
fi

# 2) Block accidentally tracked Firebase config files.
# They often contain API keys/project identifiers and must stay local.
for forbidden in "ios/Runner/GoogleService-Info.plist" "android/app/google-services.json"; do
  if git ls-files --error-unmatch "$forbidden" >/dev/null 2>&1; then
    echo >&2 ""
    echo >&2 "ERROR: Forbidden tracked secret config file: $forbidden"
    echo >&2 "Remove it from git and keep it local only."
    exit 1
  fi
done

echo "OK: no Google key patterns or tracked Firebase secret config files."
