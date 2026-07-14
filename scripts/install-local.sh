#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "error: local installation requires macOS." >&2
  exit 1
}

PUBLIC_KEY="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Sources/LumaeApp/Resources/Info.plist 2>/dev/null || true)"
if [[ -z "$PUBLIC_KEY" || "$PUBLIC_KEY" == REPLACE_WITH_* ]]; then
  echo "error: Sparkle is not configured yet." >&2
  echo "Run ./scripts/setup-updater.sh, regenerate the project, then retry." >&2
  exit 1
fi

./scripts/generate-project.sh
./scripts/build-release.sh
./scripts/sign-app.sh build/export/Lumae.app

SOURCE="build/export/Lumae.app"
DESTINATION="/Applications/Lumae.app"
BACKUP_ROOT="$HOME/Library/Application Support/Lumae/Install Backups"

osascript -e 'tell application "Lumae" to quit' >/dev/null 2>&1 || true
sleep 1

if [[ -d "$DESTINATION" ]]; then
  mkdir -p "$BACKUP_ROOT"
  TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
  BACKUP="$BACKUP_ROOT/Lumae-$TIMESTAMP.app"
  echo "Backing up existing installation to: $BACKUP"
  mv "$DESTINATION" "$BACKUP"
fi

/usr/bin/ditto "$SOURCE" "$DESTINATION"
/usr/bin/xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true
codesign --verify --deep --strict --verbose=2 "$DESTINATION"

open "$DESTINATION"
echo "Installed and launched $DESTINATION"
