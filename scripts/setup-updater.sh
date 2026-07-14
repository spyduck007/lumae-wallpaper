#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "error: Sparkle key setup must run on macOS." >&2
  exit 1
}

command -v xcodebuild >/dev/null || {
  echo "error: Xcode command-line tools are required." >&2
  exit 1
}

[[ -d Lumae.xcodeproj ]] || ./scripts/generate-project.sh

xcodebuild -resolvePackageDependencies \
  -project Lumae.xcodeproj \
  -scheme Lumae >/dev/null

find_tool() {
  local name="$1"
  local found=""
  found="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -type f -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/$name" \
    -print -quit 2>/dev/null || true)"
  [[ -n "$found" ]] || {
    echo "error: Could not find Sparkle tool '$name'. Build Lumae once in Xcode and retry." >&2
    exit 1
  }
  printf '%s\n' "$found"
}

GENERATE_KEYS="$(find_tool generate_keys)"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.lumae.wallpaper}"

"$GENERATE_KEYS" --account "$ACCOUNT"
PUBLIC_KEY="$("$GENERATE_KEYS" --account "$ACCOUNT" -p | tr -d '\r\n')"

[[ "$PUBLIC_KEY" =~ ^[A-Za-z0-9+/=]+$ ]] || {
  echo "error: Sparkle returned an invalid public key." >&2
  exit 1
}

/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" \
  Sources/LumaeApp/Resources/Info.plist

echo
echo "Sparkle updater configured."
echo "Private key account: $ACCOUNT (stored in your login Keychain)"
echo "Public key written to Sources/LumaeApp/Resources/Info.plist"
echo "Keep the private key safe; losing it prevents future updates."
