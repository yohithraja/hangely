#!/bin/bash
# Renders every built-in charm to Assets.xcassets/CharmPreviews, and a collection
# sheet to Assets/Screenshots/collection-sheet.png. Re-run after changing artwork.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(mktemp -d)"
SDK="$(xcrun --show-sdk-path --sdk macosx)"

xcrun swiftc -target arm64-apple-macos14.0 -sdk "$SDK" -swift-version 6 -O -parse-as-library \
  -o "$BUILD/previews" \
  "$ROOT"/Hangly/Models/Charm.swift \
  "$ROOT"/Hangly/Models/CharmSound.swift \
  "$ROOT"/Hangly/Models/SVGArtworkSource.swift \
  "$ROOT"/Hangly/Models/Charms/*.swift \
  "$ROOT"/Hangly/Utilities/Comparable+Clamped.swift \
  "$ROOT"/Hangly/Utilities/VectorImage.swift \
  "$ROOT"/Hangly/Utilities/RGBABitmap.swift \
  "$ROOT"/Hangly/Views/Overlay/CharmRenderer.swift \
  "$ROOT"/Hangly/Views/Overlay/CharmView.swift \
  "$ROOT"/Scripts/GenerateCharmPreviews.swift

mkdir -p "$ROOT/Assets/Screenshots"
# The collection's artwork is read straight from the designer's SVGs.
export HANGLY_CHARM_SVG_DIR="$ROOT/Assets/Charms"
"$BUILD/previews" "$ROOT/Hangly/Assets/Assets.xcassets/CharmPreviews" "$ROOT/Assets/Screenshots/collection-sheet.png"
rm -rf "$BUILD"
