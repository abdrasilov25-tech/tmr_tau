# tmr_tau

Marketplace social app (Instagram/TikTok style). Flutter + Supabase.

## Getting Started

This project is a Flutter application.

- [Flutter documentation](https://docs.flutter.dev/)

### iOS Simulator не открывается / не виден в Cursor

1. В терминале из корня проекта: `./scripts/boot_ios_simulator.sh`, затем `flutter run -d "iPhone 16e"` (или выбери устройство из `flutter devices`).
2. В Cursor/VS Code: конфигурация запуска **`tmr_tau (iOS — сначала симулятор)`** — перед `Run` поднимает Simulator и эмулятор.
3. Если пусто: **Xcode → Settings → Platforms** — установи **iOS Simulator** runtime.
4. «Завис» симулятор: **Simulator → Device → Erase All Content and Settings** или перезагрузка Mac.

### Ошибка `Mach error -308` / `simctl install` / `server died`

Это сбой **службы симулятора** или «зависшая» установка приложения, не обязательно битый plist.

**Автоматически (рекомендуется):** из **корня проекта** в терминале:
```bash
./scripts/repair_ios_simulator.sh
flutter run -d "iPhone 16e"
```

Скрипт: закрывает Simulator, `simctl shutdown all`, снимает установку приложения (`com.example.tmrTau` / `com.bazar.tmr-tau`), перезапускает **CoreSimulator** (`sudo`), удаляет `build/.../Runner.app`, снова открывает симулятор.

- Без запроса sudo: `IOS_SIM_REPAIR_SUDO=0 ./scripts/repair_ios_simulator.sh`
- С `flutter clean` + `pub get`: `IOS_SIM_FULL_CLEAN=1 ./scripts/repair_ios_simulator.sh`

В Cursor: **Terminal → Run Task… → Repair iOS Simulator (-308)**.

Вручную:
1. `xcrun simctl shutdown all` → `open -a Simulator`
2. `sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService` → снова открыть Simulator
3. Другое устройство: **Simulator → File → Open Simulator → iPhone 17 Pro**
4. Перезагрузка Mac / обновление **Xcode**, если beta iOS 26 снова падает

