#!/bin/bash
#
# Builds Hangly and packages it as a distributable disk image.
#
#   ./Scripts/build-dmg.sh                 # Production configuration (what ships)
#   ./Scripts/build-dmg.sh Release         # Release, for comparison
#
# Outputs, both under dist/:
#
#   dist/Hangly.app        the built application
#   dist/Hangly.dmg        the compressed disk image
#
# Uses only tools that ship with macOS and Xcode: xcodebuild, hdiutil, tiffutil,
# osascript. No third-party packaging dependency.
set -euo pipefail

CONFIGURATION="${1:-Production}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
WORK="$(mktemp -d)"
MOUNT_DIR=""
cleanup() {
  if [ -n "$MOUNT_DIR" ] && [ -d "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
  fi
  rm -rf "$WORK"
}
trap cleanup EXIT

APP_NAME="Hangly"
VOLUME_NAME="Hangly"
STAGING="$WORK/staging"
DERIVED="$WORK/DerivedData"

# The installer window. These must match GenerateDMGBackground.swift, which draws
# the background against the same numbers.
WINDOW_WIDTH=620
WINDOW_HEIGHT=420
ICON_SIZE=112
APP_X=170
APP_Y=238
APPLICATIONS_X=450
APPLICATIONS_Y=238

echo "==> Building $APP_NAME ($CONFIGURATION)"
xcodebuild \
  -project "$ROOT/Hangly.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED" \
  clean build \
  | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v appintentsmetadataprocessor || true

BUILT_APP="$DERIVED/Build/Products/$CONFIGURATION/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
  echo "error: build produced no app at $BUILT_APP" >&2
  exit 1
fi

echo "==> Staging"
rm -rf "$DIST"
mkdir -p "$DIST" "$STAGING/.background"
cp -R "$BUILT_APP" "$DIST/$APP_NAME.app"
cp -R "$BUILT_APP" "$STAGING/$APP_NAME.app"
ln -s /Applications "$STAGING/Applications"

# Keep the image free of anything the user did not ask to download.
find "$STAGING" -name '.DS_Store' -delete
xattr -cr "$STAGING/$APP_NAME.app"

echo "==> Drawing the background"
SDK="$(xcrun --show-sdk-path --sdk macosx)"
xcrun swiftc -target arm64-apple-macos14.0 -sdk "$SDK" -swift-version 6 -O -parse-as-library \
  -o "$WORK/background" "$ROOT/Scripts/GenerateDMGBackground.swift"
"$WORK/background" "$ROOT/Assets/Charms/Nazar Boncuğu.svg" "$WORK/bg"
# One TIFF carrying both resolutions is how a disk image gets a Retina background.
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" \
  -out "$STAGING/.background/background.tiff" >/dev/null

# The mounted volume takes the app's own icon. Built from the icon set rather than
# copied out of the bundle: Xcode's generated AppIcon.icns carries only a few of the
# sizes, and a volume icon is asked for at all of them.
VOLUME_ICON="$WORK/VolumeIcon.icns"
ICONSET="$WORK/VolumeIcon.iconset"
mkdir -p "$ICONSET"
# Every size up to 512 px. A volume icon is never drawn larger than Get Info shows
# it, and carrying the 1024 slice as well costs a megabyte of the download for a
# resolution nothing asks a disk for.
ICON_SOURCE="$ROOT/Hangly/Assets/Assets.xcassets/AppIcon.appiconset"
if cp "$ICON_SOURCE"/icon_16x16*.png "$ICON_SOURCE"/icon_32x32*.png \
      "$ICON_SOURCE"/icon_128x128*.png "$ICON_SOURCE"/icon_256x256*.png \
      "$ICON_SOURCE"/icon_512x512.png "$ICONSET/" 2>/dev/null; then
  if iconutil -c icns "$ICONSET" -o "$VOLUME_ICON" 2>/dev/null; then
    echo "    volume icon: $(du -k "$VOLUME_ICON" | cut -f1) KB from $(ls "$ICONSET" | wc -l | tr -d ' ') sizes"
  else
    echo "note: iconutil could not build the volume icon; the image will use the default"
  fi
fi

echo "==> Creating a writable image"
RW_DMG="$WORK/$APP_NAME-rw.dmg"
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "$VOLUME_NAME" \
  -fs HFS+ \
  -format UDRW \
  -ov \
  "$RW_DMG" >/dev/null

# Mounted at the standard location and visible: Finder addresses a volume by name,
# and cannot see one mounted elsewhere or hidden from browsing — which is the whole
# reason this step exists, since only Finder writes the .DS_Store.
if [ -d "/Volumes/$VOLUME_NAME" ]; then
  hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet 2>/dev/null || true
fi
hdiutil attach "$RW_DMG" -noautoopen >/dev/null
MOUNT_DIR="/Volumes/$VOLUME_NAME"
if [ ! -d "$MOUNT_DIR" ]; then
  echo "error: the image did not mount at $MOUNT_DIR" >&2
  exit 1
fi

echo "==> Laying out the window"
# Finder owns the icon positions and the background picture; both live in the
# volume's .DS_Store, which only Finder writes.
osascript <<APPLESCRIPT >/dev/null
  tell application "Finder"
    tell disk "$VOLUME_NAME"
      open
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set the bounds of container window to {200, 140, 200 + $WINDOW_WIDTH, 140 + $WINDOW_HEIGHT}
      set viewOptions to the icon view options of container window
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to $ICON_SIZE
      set text size of viewOptions to 12
      set background picture of viewOptions to file ".background:background.tiff"
      set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
      set position of item "Applications" of container window to {$APPLICATIONS_X, $APPLICATIONS_Y}
      update without registering applications
      close
    end tell
  end tell
APPLESCRIPT

# Give Finder a moment to flush .DS_Store before the volume is torn down.
sync
sleep 2

# Nothing from this machine's filesystem journal belongs in a downloadable image.
rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes" "$MOUNT_DIR/.TemporaryItems" 2>/dev/null || true
mkdir -p "$MOUNT_DIR/.fseventsd" && touch "$MOUNT_DIR/.fseventsd/no_log"

# The volume icon goes on now rather than being staged: Finder's pass over the
# mounted volume discards a staged one. The file alone does nothing either — the
# volume needs its custom-icon bit set on top.
if [ -f "$VOLUME_ICON" ]; then
  cp "$VOLUME_ICON" "$MOUNT_DIR/.VolumeIcon.icns"
  if SetFile -a C "$MOUNT_DIR" 2>/dev/null; then
    echo "    volume icon applied and its bit set"
  else
    echo "note: could not set the volume icon bit (SetFile unavailable)"
  fi
  sync
fi

hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""

echo "==> Compressing"
# ULFO (LZFSE) and UDZO (zlib) are both universally readable on the versions of
# macOS this app supports; whichever comes out smaller is the one shipped.
hdiutil convert "$RW_DMG" -format ULFO -o "$WORK/lzfse.dmg" >/dev/null
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$WORK/zlib.dmg" >/dev/null
LZFSE_SIZE=$(stat -f%z "$WORK/lzfse.dmg")
ZLIB_SIZE=$(stat -f%z "$WORK/zlib.dmg")
if [ "$LZFSE_SIZE" -le "$ZLIB_SIZE" ]; then
  cp "$WORK/lzfse.dmg" "$DIST/$APP_NAME.dmg"
  FORMAT="ULFO (LZFSE)"
else
  cp "$WORK/zlib.dmg" "$DIST/$APP_NAME.dmg"
  FORMAT="UDZO (zlib-9)"
fi

echo "==> Verifying"
hdiutil verify "$DIST/$APP_NAME.dmg" >/dev/null && echo "    checksum ok"
codesign --verify --deep --strict "$DIST/$APP_NAME.app" && echo "    signature ok"

printf '\n'
echo "Built $CONFIGURATION"
echo "  app     $DIST/$APP_NAME.app  ($(du -sh "$DIST/$APP_NAME.app" | cut -f1 | tr -d ' '))"
echo "  image   $DIST/$APP_NAME.dmg  ($(du -sh "$DIST/$APP_NAME.dmg" | cut -f1 | tr -d ' '), $FORMAT)"
echo "          lzfse $(echo "scale=1; $LZFSE_SIZE/1048576" | bc) MB vs zlib $(echo "scale=1; $ZLIB_SIZE/1048576" | bc) MB"
