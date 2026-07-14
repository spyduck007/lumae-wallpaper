#!/bin/bash
set -euo pipefail
APP="${1:-build/export/Lumae.app}"; [[ -d "$APP" ]] || { echo "error: missing $APP" >&2; exit 1; }
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
if [[ -n "$IDENTITY" ]]; then codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" "$APP"; else codesign --force --deep --sign - "$APP"; fi
codesign --verify --deep --strict --verbose=2 "$APP"
