#!/bin/sh
# CocoaPods-пакеты Agora не кладут готовые .dSYM в Pods, из‑за этого App Store Connect
# и Crashlytics ругаются на «Upload Symbols Failed». Генерируем dSYM из бинарников
# device-слайсов xcframework (UUID совпадает с тем, что в архиве).
set -eu

case "${CONFIGURATION:-}" in
  Debug) exit 0 ;;
esac

DEST="${DWARF_DSYM_FOLDER_PATH:-}"
if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
  echo "note: copy_agora_dsyms: DWARF_DSYM_FOLDER_PATH missing, skip"
  exit 0
fi

PODS="${PODS_ROOT:-}"
if [ -z "$PODS" ] || [ ! -d "$PODS" ]; then
  exit 0
fi

gen_one() {
  fw_dir=$1
  name=$(basename "$fw_dir" .framework)
  binary="${fw_dir}/${name}"
  if [ ! -f "$binary" ]; then
    return 0
  fi
  out="${DEST}/${name}.framework.dSYM"
  if [ -d "$out" ]; then
    return 0
  fi
  echo "copy_agora_dsyms: dsymutil ${name}"
  # Предупреждения «no debug symbols» для Agora — ожидаемы; UUID в dSYM всё равно нужен загрузчику.
  dsymutil "$binary" -o "$out" 2>/dev/null || true
}

for root in \
  "${PODS}/AgoraRtcEngine_iOS" \
  "${PODS}/AgoraInfra_iOS" \
  "${PODS}/AgoraIrisRTC_iOS"
do
  [ -d "$root" ] || continue
  find "$root" -path '*.xcframework/ios-arm64*/*.framework' -type d ! -path '*simulator*' 2>/dev/null |
    while IFS= read -r fw; do
      gen_one "$fw"
    done
done

exit 0
