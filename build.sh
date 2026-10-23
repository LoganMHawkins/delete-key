#!/bin/bash
# Builds DeleteKey.app (background-only, no Dock icon).
#
#   ./build.sh             build DeleteKey.app next to this script
#   ./build.sh --install   build, copy to ~/Applications, and launch it
#   ./build.sh --release   build with Developer ID, notarize, staple, and zip to dist/
#
# Env: VERSION (default 1.0), SIGN_ID (signing identity), NOTARY_PROFILE (default
# "deletekey-notary", created once with `xcrun notarytool store-credentials`).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-}"
VERSION="${VERSION:-1.0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-deletekey-notary}"
APP="DeleteKey.app"
SRC="$PWD"

find_identity() { security find-identity -v -p codesigning | sed -n "s/.*\"\\($1:[^\"]*\\)\".*/\\1/p" | head -1; }

if [[ "$MODE" == "--release" ]]; then
  SIGN_ID="${SIGN_ID:-$(find_identity 'Developer ID Application')}"
  if [[ -z "$SIGN_ID" ]]; then
    echo "No 'Developer ID Application' certificate in your keychain."
    echo "Create one in Xcode: Settings > Accounts > Manage Certificates > + > Developer ID Application."
    exit 1
  fi
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 || {
    echo "No notarization login named '$NOTARY_PROFILE'. Create it once with:"
    echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id <your Apple ID> --team-id <TEAM ID>"
    echo "(it asks for an app-specific password from appleid.apple.com)"
    exit 1
  }
else
  # A stable identity keeps the Accessibility approval valid across rebuilds
  # (ad hoc signatures change every build). Falls back to ad hoc.
  SIGN_ID="${SIGN_ID:-$(find_identity 'Apple Development')}"
fi

# Build and sign in a temp dir: folders like ~/Documents add attributes that codesign rejects.
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
mkdir -p "$BUILD/$APP/Contents/MacOS"
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos13.0" main.swift -o "$BUILD/DeleteKey-$ARCH"
done
lipo -create "$BUILD/DeleteKey-arm64" "$BUILD/DeleteKey-x86_64" -output "$BUILD/$APP/Contents/MacOS/DeleteKey"
cd "$BUILD"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>ca.theboldbureau.deletekey</string>
  <key>CFBundleName</key><string>DeleteKey</string>
  <key>CFBundleExecutable</key><string>DeleteKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF

if [[ "$MODE" == "--release" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
else
  codesign --force --sign "${SIGN_ID:--}" "$APP"
fi

if [[ "$MODE" == "--release" ]]; then
  ditto -c -k --keepParent "$APP" "$BUILD/notarize.zip"
  echo "Submitting to Apple for notarization (usually a few minutes)..."
  xcrun notarytool submit "$BUILD/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute -vv "$APP"
  mkdir -p "$SRC/dist"
  ditto -c -k --keepParent "$APP" "$SRC/dist/DeleteKey-$VERSION.zip"
  echo "Release ready: dist/DeleteKey-$VERSION.zip"
  exit 0
fi

rm -rf "$SRC/$APP"; ditto --noextattr --norsrc "$APP" "$SRC/$APP"
echo "Built $APP"

if [[ "$MODE" == "--install" ]]; then
  DEST="$HOME/Applications"
  OLD_AGENT="$HOME/Library/LaunchAgents/ca.theboldbureau.deletekey.plist"
  mkdir -p "$DEST"
  # Earlier versions started at login via a LaunchAgent; the app now registers itself.
  if [[ -f "$OLD_AGENT" ]]; then launchctl unload "$OLD_AGENT" 2>/dev/null || true; rm -f "$OLD_AGENT"; fi
  pkill -x DeleteKey 2>/dev/null || true
  sleep 1
  rm -rf "$DEST/$APP"; cp -R "$APP" "$DEST/"
  open "$DEST/$APP"
  echo "Installed and started. Grant Accessibility access to DeleteKey if prompted."
fi
