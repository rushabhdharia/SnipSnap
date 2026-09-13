#!/bin/bash
#
# Builds SnipSnap.app from the Swift package and installs it to /Applications.
# Works with the Command Line Tools toolchain — no Xcode, no sudo.
#
# Usage:
#   ./make.sh              build, bundle, install to /Applications, launch
#   ./make.sh -y           don't prompt before replacing an existing install
#   ./make.sh --no-install build and bundle into ./build only

set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="SnipSnap"
BUNDLE_ID="com.rushabhdharia.snipsnap"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
INSTALL_DIR="/Applications"

ASSUME_YES=0
DO_INSTALL=1
for arg in "$@"; do
  case "$arg" in
    -y|--yes)      ASSUME_YES=1 ;;
    --no-install)  DO_INSTALL=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

echo "==> Building release binary"
swift build -c release --product "$APP_NAME"
BIN="$(swift build -c release --show-bin-path)/$APP_NAME"
[ -x "$BIN" ] || { echo "build produced no binary at $BIN" >&2; exit 1; }

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Generating app icon"
if ! ./scripts/make-icon.sh "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
  echo "    (icon generation skipped — app will use the default icon)"
  /usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$APP/Contents/Info.plist" 2>/dev/null || true
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --strict "$APP" && echo "    signature ok"

if [ "$DO_INSTALL" -eq 0 ]; then
  echo "==> Done: $APP"
  exit 0
fi

DEST="$INSTALL_DIR/$APP_NAME.app"
if [ -e "$DEST" ] && [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "Replace existing $DEST ? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) ;;
    *) echo "Left existing install in place. Bundle is at $APP"; exit 0 ;;
  esac
fi

echo "==> Installing to $DEST"
osascript -e 'tell application "SnipSnap" to quit' 2>/dev/null || true
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$DEST"
cp -R "$APP" "$DEST"

echo "==> Launching"
open "$DEST"

cat <<EOF

Installed. Press  ⌘⌃V  (Command–Control–V) to open the clipboard panel.

First run:
  • Grant Accessibility when prompted (System Settings ▸ Privacy & Security ▸
    Accessibility) so items paste straight into the app you were using.
    Without it, selecting an item just puts it on the clipboard for ⌘V.
  • Quit from the menu bar icon (top-right).
EOF
