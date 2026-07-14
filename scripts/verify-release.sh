#!/bin/bash
set -euo pipefail
APP="${1:-build/export/Lumae.app}"; DMG="${2:-dist/Lumae-0.1.0.dmg}"
codesign --verify --deep --strict --verbose=2 "$APP"; spctl --assess --type execute --verbose=4 "$APP" || true
if [[ -f "$DMG" ]]; then hdiutil verify "$DMG"; xcrun stapler validate "$DMG" || true; fi
