#!/bin/bash
set -euo pipefail

APP="${1:-/Applications/Lumae.app}"
REPORT_DIR="$HOME/Desktop/Lumae Diagnostics"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/lumae-diagnostics-$TIMESTAMP.txt"

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "error: diagnostics require macOS." >&2
  exit 1
}
[[ -d "$APP" ]] || {
  echo "error: missing $APP" >&2
  exit 1
}

mkdir -p "$REPORT_DIR"

{
  echo "Lumae installed-build diagnostics"
  echo "Generated: $(date)"
  echo "App: $APP"
  echo

  echo "=== macOS ==="
  sw_vers
  uname -m
  echo

  echo "=== Bundle version ==="
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" || true
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" || true
  echo

  echo "=== Signature verification ==="
  codesign --verify --deep --strict --verbose=4 "$APP" 2>&1 || true
  echo

  echo "=== Signature details ==="
  codesign -dv --verbose=4 "$APP" 2>&1 || true
  echo

  echo "=== Embedded code ==="
  find "$APP/Contents" -maxdepth 5 \
    \( -name '*.framework' -o -name '*.xpc' -o -name '*.app' \) \
    -print | sort
  echo

  echo "=== Gatekeeper assessment ==="
  spctl --assess --type execute --verbose=4 "$APP" 2>&1 || true
  echo

  echo "=== Recent Lumae unified logs ==="
  log show --last 10m \
    --style compact \
    --predicate 'process == "Lumae" OR subsystem CONTAINS[c] "sparkle"' \
    2>&1 | tail -n 500 || true
  echo

  echo "=== Latest crash report ==="
  LATEST="$(find "$HOME/Library/Logs/DiagnosticReports" \
    -maxdepth 1 -type f \( -name 'Lumae*.ips' -o -name 'Lumae*.crash' \) \
    -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1 || true)"
  if [[ -n "$LATEST" ]]; then
    echo "Crash report: $LATEST"
    cat "$LATEST"
  else
    echo "No Lumae crash report was found."
  fi
} > "$REPORT" 2>&1

echo "Diagnostics written to: $REPORT"
echo "Upload that text file if the rebuilt installed app still crashes."
