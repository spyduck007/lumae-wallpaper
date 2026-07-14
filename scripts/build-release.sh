#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

command -v xcodebuild >/dev/null || {
  echo "error: xcodebuild requires macOS with Xcode." >&2
  exit 1
}

[[ -d Lumae.xcodeproj ]] || ./scripts/generate-project.sh

DERIVED_DATA="$ROOT/build/ReleaseDerivedData"
EXPORT_DIR="$ROOT/build/export"
APP_SOURCE="$DERIVED_DATA/Build/Products/Release/Lumae.app"
IDENTITY="${DEVELOPER_ID_APPLICATION:-}"
TEAM="${DEVELOPMENT_TEAM:-}"

rm -rf "$DERIVED_DATA" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

if [[ -n "$IDENTITY" ]]; then
  [[ -n "$TEAM" ]] || {
    echo "error: DEVELOPMENT_TEAM must be set with DEVELOPER_ID_APPLICATION." >&2
    exit 1
  }

  echo "Building a Developer ID signed Release app..."
  xcodebuild \
    -project Lumae.xcodeproj \
    -scheme Lumae \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES
else
  echo "Building an Xcode-managed ad-hoc Release app for local testing..."
  xcodebuild \
    -project Lumae.xcodeproj \
    -scheme Lumae \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    clean build \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY=- \
    DEVELOPMENT_TEAM= \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES
fi

[[ -d "$APP_SOURCE" ]] || {
  echo "error: Xcode did not produce $APP_SOURCE" >&2
  exit 1
}

/usr/bin/ditto "$APP_SOURCE" "$EXPORT_DIR/Lumae.app"

codesign --verify --deep --strict --verbose=2 "$EXPORT_DIR/Lumae.app"
echo "App: $EXPORT_DIR/Lumae.app"
