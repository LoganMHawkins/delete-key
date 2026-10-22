#!/bin/bash
# Builds DeleteKey.app (background-only, no Dock icon) next to this script.
# Run with --install to copy it to ~/Applications and start it at login.
set -euo pipefail
cd "$(dirname "$0")"

SRC="$PWD"
# Build and sign in a temp dir: folders like ~/Documents add attributes that codesign rejects.
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
APP="DeleteKey.app"
mkdir -p "$BUILD/$APP/Contents/MacOS"
swiftc -O main.swift -o "$BUILD/$APP/Contents/MacOS/DeleteKey"
cd "$BUILD"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>ca.theboldbureau.deletekey</string>
  <key>CFBundleName</key><string>DeleteKey</string>
  <key>CFBundleExecutable</key><string>DeleteKey</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
# A stable signing identity keeps the Accessibility approval valid across rebuilds
# (ad hoc signatures change every build). Override with SIGN_ID, falls back to ad hoc.
SIGN_ID="${SIGN_ID:-$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)}"
codesign --force --sign "${SIGN_ID:--}" "$APP"
rm -rf "$SRC/$APP"; ditto --noextattr --norsrc "$APP" "$SRC/$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  DEST="$HOME/Applications"
  PLIST="$HOME/Library/LaunchAgents/ca.theboldbureau.deletekey.plist"
  mkdir -p "$DEST" "$HOME/Library/LaunchAgents"
  launchctl unload "$PLIST" 2>/dev/null || true
  pkill -x DeleteKey 2>/dev/null || true
  rm -rf "$DEST/$APP"; cp -R "$APP" "$DEST/"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>ca.theboldbureau.deletekey</string>
  <key>ProgramArguments</key><array><string>$DEST/$APP/Contents/MacOS/DeleteKey</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/DeleteKey.log</string>
</dict></plist>
EOF
  launchctl load "$PLIST"
  echo "Installed and started. Grant Accessibility access to DeleteKey when prompted."
fi
