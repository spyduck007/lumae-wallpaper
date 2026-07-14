#!/bin/bash
set -euo pipefail

APP="${1:-build/export/Lumae.app}"
[[ -d "$APP" ]] || {
  echo "error: missing $APP" >&2
  exit 1
}

# Sparkle embeds nested frameworks and XPC services. They must be signed by
# Xcode during the build in dependency order; do not re-sign the finished app
# with `codesign --deep`, which can produce a bundle that launches and then
# crashes when an embedded helper starts.
codesign --verify --deep --strict --verbose=2 "$APP"

IDENTITY_SUMMARY="$(codesign -dv --verbose=2 "$APP" 2>&1 | grep '^Authority=' || true)"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" && -z "$IDENTITY_SUMMARY" ]]; then
  echo "error: this app is not Developer ID signed." >&2
  echo "Re-run build-release.sh with DEVELOPER_ID_APPLICATION and DEVELOPMENT_TEAM set." >&2
  exit 1
fi

echo "Signature verified: $APP"
