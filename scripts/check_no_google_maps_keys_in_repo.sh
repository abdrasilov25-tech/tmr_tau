#!/usr/bin/env bash
# Fail if a Google Maps/Browser-style API key pattern appears in git-tracked files.
set -euo pipefail
cd "$(dirname "$0")/.."
if git grep -n --extended-regexp 'AIzaSy[0-9A-Za-z_-]{10,}' -- . \
  ':(exclude)docs/google-maps-release-safety.md' 2>/dev/null; then
  echo >&2 ""
  echo >&2 "ERROR: Possible Google API key (AIzaSy...) in tracked files. Remove it from git."
  exit 1
fi
echo "OK: no AIzaSy... pattern in tracked sources."
