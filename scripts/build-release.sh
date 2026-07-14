#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
command -v xcodebuild >/dev/null || { echo "error: xcodebuild requires macOS with Xcode" >&2; exit 1; }
[[ -d Lumae.xcodeproj ]] || scripts/generate-project.sh
rm -rf build/Release.xcarchive build/export
xcodebuild -project Lumae.xcodeproj -scheme Lumae -configuration Release -archivePath build/Release.xcarchive archive CODE_SIGNING_ALLOWED=NO
mkdir -p build/export
cp -R build/Release.xcarchive/Products/Applications/Lumae.app build/export/
echo "App: build/export/Lumae.app"
