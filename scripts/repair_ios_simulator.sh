#!/usr/bin/env bash
# Исправление Mach -308 / simctl install (server died): перезапуск CoreSimulator + снятие битой установки.
# Запуск из корня репозитория: ./scripts/repair_ios_simulator.sh
# Без sudo: IOS_SIM_REPAIR_SUDO=0 ./scripts/repair_ios_simulator.sh
# С полной очисткой Flutter: IOS_SIM_FULL_CLEAN=1 ./scripts/repair_ios_simulator.sh

set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== repair_ios_simulator: $ROOT =="

echo "1) Закрываю Simulator..."
osascript -e 'quit app "Simulator"' 2>/dev/null || true
sleep 1

echo "2) Останавливаю все симуляторы..."
xcrun simctl shutdown all 2>/dev/null || true
sleep 2

echo "3) Удаляю приложение с симулятора (если осталась «битая» установка)..."
for BUNDLE_ID in com.example.tmrTau "com.bazar.tmr-tau"; do
  xcrun simctl uninstall booted "$BUNDLE_ID" 2>/dev/null || true
done

if [[ "${IOS_SIM_REPAIR_SUDO:-1}" != "0" ]]; then
  echo "4) Перезапуск службы CoreSimulator (введи пароль, если спросит)..."
  sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService 2>/dev/null || {
    echo "   Не удалось перезапустить службу (sudo). Вручную:"
    echo "   sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService"
  }
else
  echo "4) Пропуск sudo (IOS_SIM_REPAIR_SUDO=0)"
fi
sleep 2

echo "5) Открываю Simulator..."
open -a Simulator
sleep 4

echo "6) Загружаю iPhone 16e..."
xcrun simctl boot "iPhone 16e" 2>/dev/null || true

echo "7) Удаляю собранный Runner.app (часто помогает при повторной установке)..."
rm -rf "$ROOT/build/ios/iphonesimulator/Runner.app" 2>/dev/null || true

if [[ "${IOS_SIM_FULL_CLEAN:-0}" == "1" ]]; then
  echo "8) Полная очистка Flutter (IOS_SIM_FULL_CLEAN=1)..."
  flutter clean
  flutter pub get
else
  echo "8) Полная очистка пропущена. При необходимости: IOS_SIM_FULL_CLEAN=1 $0"
fi

echo ""
echo "Готово. Устройства:"
flutter devices 2>/dev/null || true
echo ""
echo "Дальше:"
echo "  cd \"$ROOT\" && flutter run -d \"iPhone 16e\""
