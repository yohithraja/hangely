#!/bin/bash
# Rebuilds Assets.xcassets/AppIcon.appiconset from the master artwork.
# Re-run after replacing Assets/Branding/AppIcon-master.png.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
SDK="$(xcrun --show-sdk-path --sdk macosx)"

xcrun swiftc -target arm64-apple-macos14.0 -sdk "$SDK" -swift-version 6 -O -parse-as-library \
  -o "$BUILD/appicon" "$ROOT/Scripts/GenerateAppIcon.swift"

"$BUILD/appicon" \
  "$ROOT/Assets/Branding/AppIcon-master.png" \
  "$ROOT/Hangly/Assets/Assets.xcassets/AppIcon.appiconset"
