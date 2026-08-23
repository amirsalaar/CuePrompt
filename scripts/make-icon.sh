#!/bin/bash
# Generate AppIcon.icns from the source PNG into a bundle's Resources directory.
#
# Shared by scripts/build.sh and .github/workflows/release.yml — the release
# workflow assembles its own bundle, and when this logic lived only in build.sh
# every published .app shipped without an icon.
#
# Usage: make-icon.sh <path-to-Contents/Resources>
set -euo pipefail

RESOURCES_DIR="${1:?usage: make-icon.sh <path-to-Contents/Resources>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_SOURCE="$SCRIPT_DIR/../Sources/Resources/AppIcon-source.png"

if [ ! -f "$ICON_SOURCE" ]; then
  echo "⚠️  $ICON_SOURCE not found — skipping icon generation."
  exit 0
fi

ICONSET_DIR="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET_DIR" "$RESOURCES_DIR"

# "<pixel size> <iconset filename>" — the set macOS expects for a full icon.
for pair in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
  "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
  "512 icon_512x512" "1024 icon_512x512@2x"; do
  SIZE="${pair%% *}"
  NAME="${pair#* }"
  sips -z "$SIZE" "$SIZE" "$ICON_SOURCE" --out "$ICONSET_DIR/${NAME}.png" >/dev/null 2>&1
done

iconutil -c icns -o "$RESOURCES_DIR/AppIcon.icns" "$ICONSET_DIR"
rm -rf "$(dirname "$ICONSET_DIR")"

echo "  App icon installed: $RESOURCES_DIR/AppIcon.icns"
