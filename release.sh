#!/bin/bash
#
# Builds SnipSnap.app and packages it as a versioned zip for distribution
# (e.g. as a GitHub Release asset that a Homebrew cask points at).
#
# Usage:
#   ./release.sh 1.0.0
#
# Produces:
#   dist/SnipSnap-1.0.0.zip
# and prints its sha256, which a cask formula needs verbatim.

set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:?usage: ./release.sh <version>, e.g. ./release.sh 1.0.0}"
APP_NAME="SnipSnap"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
ZIP="$DIST_DIR/$APP_NAME-$VERSION.zip"

./make.sh --no-install

mkdir -p "$DIST_DIR"
rm -f "$ZIP"

echo "==> Zipping $APP -> $ZIP"
# ditto (not `zip`) is what Apple recommends for .app bundles: it preserves
# the bundle structure, resource forks and extended attributes so the
# codesign inside survives the round trip intact.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

cat <<EOF

==> Done: $ZIP
    sha256: $SHA

Next: upload $ZIP as a GitHub Release asset tagged v$VERSION, then put this
sha256 and the release URL into the cask formula.
EOF
