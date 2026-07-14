#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9]+)*$ ]] || {
  echo "usage: $0 <version, e.g. 0.2.0>" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || {
  echo "error: release publishing must run on macOS." >&2
  exit 1
}
command -v gh >/dev/null || {
  echo "error: GitHub CLI is required: brew install gh" >&2
  exit 1
}
command -v xcodebuild >/dev/null || {
  echo "error: Xcode command-line tools are required." >&2
  exit 1
}

[[ -z "$(git status --porcelain)" ]] || {
  echo "error: commit all changes before publishing a release." >&2
  exit 1
}

TAG="v$VERSION"
DMG="dist/Lumae-$VERSION.dmg"
UPDATES="release/updates"
ACCOUNT="${SPARKLE_KEY_ACCOUNT:-com.lumae.wallpaper}"

./scripts/build-release.sh

BUILT_APP="build/export/Lumae.app"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILT_APP/Contents/Info.plist")"
BUILT_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BUILT_APP/Contents/Info.plist")"

if [[ "$BUILT_VERSION" != "$VERSION" ]]; then
  echo "error: requested release $VERSION, but Xcode built $BUILT_VERSION ($BUILT_NUMBER)." >&2
  echo "The release was not published. Regenerate the project and verify project.yml." >&2
  exit 1
fi

[[ "$BUILT_NUMBER" =~ ^[0-9]+$ ]] || {
  echo "error: built app has invalid build number: $BUILT_NUMBER" >&2
  exit 1
}

echo "Verified release bundle: Lumae $BUILT_VERSION ($BUILT_NUMBER)"
./scripts/sign-app.sh "$BUILT_APP"
./scripts/create-dmg.sh "$BUILT_APP" "$DMG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
  ./scripts/notarize-app.sh "$DMG"
else
  echo "warning: NOTARY_PROFILE is not set; publishing a non-notarized build."
fi

xcodebuild -resolvePackageDependencies -project Lumae.xcodeproj -scheme Lumae >/dev/null
GENERATE_APPCAST="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
  -type f -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
  -print -quit 2>/dev/null || true)"
[[ -x "$GENERATE_APPCAST" ]] || {
  echo "error: Could not find Sparkle generate_appcast tool." >&2
  exit 1
}

rm -rf "$UPDATES"
mkdir -p "$UPDATES"
cp "$DMG" "$UPDATES/"

"$GENERATE_APPCAST" \
  --account "$ACCOUNT" \
  --download-url-prefix "https://github.com/spyduck007/lumae-wallpaper/releases/download/$TAG/" \
  --link "https://github.com/spyduck007/lumae-wallpaper" \
  "$UPDATES"

cp "$UPDATES/appcast.xml" appcast.xml

git add appcast.xml
git commit -m "Publish Lumae $VERSION update feed"
git tag -a "$TAG" -m "Lumae $VERSION"

# Publish the signed archive before exposing the new feed on main.
git push origin "$TAG"
gh release create "$TAG" "$DMG" \
  --repo spyduck007/lumae-wallpaper \
  --title "Lumae $VERSION" \
  --generate-notes
git push origin main

./scripts/verify-release.sh build/export/Lumae.app "$DMG"
echo "Published $TAG and updated appcast.xml."
