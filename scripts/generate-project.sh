#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
command -v xcodegen >/dev/null || { echo "error: install XcodeGen: brew install xcodegen" >&2; exit 1; }
xcodegen generate --spec project.yml

PBXPROJ="$ROOT/Lumae.xcodeproj/project.pbxproj"
if ! grep -q 'Assets.xcassets' "$PBXPROJ"; then
  echo "error: generated project does not include Assets.xcassets" >&2
  exit 1
fi
if ! grep -q 'PBXResourcesBuildPhase' "$PBXPROJ"; then
  echo "error: generated project has no resources build phase" >&2
  exit 1
fi

echo "Generated $ROOT/Lumae.xcodeproj with compiled asset catalog"
