#!/usr/bin/env bash
# Поднимает Simulator и список устройств Flutter (без set -e — часть команд может вернуть не 0).
cd "$(dirname "$0")/.."
open -a Simulator 2>/dev/null || true
flutter emulators --launch apple_ios_simulator 2>/dev/null || true
echo "Готово. Устройства:"
flutter devices
