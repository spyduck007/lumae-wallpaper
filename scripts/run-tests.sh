#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
python3 -m unittest discover -s tests -v
if command -v swift >/dev/null; then swift test; else echo "note: Swift unavailable; skipped Swift tests (run on macOS)."; fi
if command -v xcodebuild >/dev/null; then [[ -d Lumae.xcodeproj ]] || scripts/generate-project.sh; xcodebuild test -project Lumae.xcodeproj -scheme Lumae -destination 'platform=macOS'; fi
