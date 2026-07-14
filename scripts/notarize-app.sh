#!/bin/bash
set -euo pipefail
DMG="${1:-dist/Lumae-0.1.0.dmg}"; : "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an xcrun notarytool keychain profile}"
[[ -f "$DMG" ]] || { echo "error: missing $DMG" >&2; exit 1; }
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"; xcrun stapler validate "$DMG"
