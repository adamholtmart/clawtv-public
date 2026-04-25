#!/usr/bin/env bash
# Fetch the TVVLCKit binary framework into Vendor/.
# The binary is too large for git; the project depends on it at build time.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendor/TVVLCKit-binary"
URL="https://download.videolan.org/cocoapods/prod/TVVLCKit-3.6.0-d2bf96d8-3a7c9c81.tar.xz"

if [ -d "$DEST/TVVLCKit.xcframework" ]; then
  echo "TVVLCKit already present at $DEST"
  exit 0
fi

mkdir -p "$DEST"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading TVVLCKit..."
curl -fL "$URL" -o "$TMP/tvvlckit.tar.xz"

echo "Extracting..."
tar -xJf "$TMP/tvvlckit.tar.xz" -C "$DEST" --strip-components=1

echo "Done. TVVLCKit installed to $DEST"
