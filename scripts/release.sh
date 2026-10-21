#!/bin/zsh
# Builds, signs with Developer ID, notarizes and verifies a distributable fmev zip.
#
# One-time setup (stores notary credentials in your keychain):
#   xcrun notarytool store-credentials fmev --apple-id <you@example.com> --team-id WH6Z8S5J2L
#
# Usage: scripts/release.sh <version>  (must match Sources/fmev/Version.swift)
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${1:?usage: scripts/release.sh <version>}"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application: Matthew Rubens (WH6Z8S5J2L)}"
PROFILE="${NOTARY_PROFILE:-fmev}"
OUT="dist"
ZIP="$OUT/fmev-$VERSION-macos-arm64.zip"

SOURCE_VERSION="$(sed -n 's/^let fmevVersion = "\(.*\)"$/\1/p' Sources/fmev/Version.swift)"
if [ "$VERSION" != "$SOURCE_VERSION" ]; then
  echo "Version $VERSION doesn't match Sources/fmev/Version.swift ($SOURCE_VERSION)" >&2
  exit 1
fi

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
