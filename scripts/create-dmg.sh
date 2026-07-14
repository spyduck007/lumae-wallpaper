#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
APP="${1:-build/export/Lumae.app}"; OUT="${2:-dist/Lumae-0.1.0.dmg}"
[[ -d "$APP" ]] || { echo "error: missing $APP; run build-release.sh" >&2; exit 1; }
command -v create-dmg >/dev/null || { echo "error: install create-dmg: brew install create-dmg" >&2; exit 1; }
mkdir -p "$(dirname "$OUT")"; rm -f "$OUT"
create-dmg --volname "Lumae" --volicon Sources/LumaeApp/Resources/Assets.xcassets/AppIcon.appiconset/icon_512.png --window-pos 200 120 --window-size 640 420 --icon-size 128 --icon "Lumae.app" 170 190 --hide-extension "Lumae.app" --app-drop-link 470 190 "$OUT" "$APP"
