#!/bin/zsh
# Builds, signs with Developer ID, notarizes and verifies a distributable fmev zip.
#
# One-time setup (stores notary credentials in your keychain):
#   xcrun notarytool store-credentials fmev --apple-id <you@example.com> --team-id WH6Z8S5J2L
#
# Usage: scripts/release.sh [version]
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Matthew Rubens (WH6Z8S5J2L)}"
PROFILE="${NOTARY_PROFILE:-fmev}"
OUT="dist"
ZIP="$OUT/fmev-$VERSION-macos-arm64.zip"

rm -rf "$OUT" && mkdir -p "$OUT/fmev-$VERSION"
BUILD="${BUILD_DIR:-.build}"
swift build -c release --arch arm64 --scratch-path "$BUILD"
BIN="$(swift build -c release --arch arm64 --scratch-path "$BUILD" --show-bin-path)"
cp "$BIN/fmev" README.md "$OUT/fmev-$VERSION/"

# Hardened runtime and a secure timestamp are both required for notarization.
codesign --force --options runtime --timestamp --identifier ai.fmev.server \
  --sign "$IDENTITY" "$OUT/fmev-$VERSION/fmev"
codesign --verify --strict --verbose=2 "$OUT/fmev-$VERSION/fmev"

ditto -c -k --keepParent "$OUT/fmev-$VERSION" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

# A bare executable can't be stapled; Gatekeeper checks the ticket online on first run.
spctl --assess --type install --verbose "$OUT/fmev-$VERSION/fmev" 2>&1 || true
shasum -a 256 "$ZIP"
echo "Ready: $ZIP"
