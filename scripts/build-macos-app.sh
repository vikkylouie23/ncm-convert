#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="NCM Local Converter"
APP_DIR="$ROOT_DIR/release/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
WEB_DIR="$RESOURCES_DIR/web"
BUILD_DIR="$ROOT_DIR/.native-build"
ZIP_PATH="$ROOT_DIR/release/$APP_NAME.app.zip"
ICON_MASTER_PNG="$BUILD_DIR/AppIcon.png"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
ICON_PATH="$BUILD_DIR/AppIcon.icns"

setopt null_glob

LEGACY_RELEASE_DIRS=("$ROOT_DIR"/release/"$APP_NAME"-darwin-*)

rm -rf "$APP_DIR" "$ZIP_PATH" "$BUILD_DIR" "${LEGACY_RELEASE_DIRS[@]}"
rm -f "$ROOT_DIR/release/.DS_Store"
mkdir -p "$MACOS_DIR" "$WEB_DIR" "$BUILD_DIR"

cp -R "$ROOT_DIR/dist/." "$WEB_DIR/"
cp "$ROOT_DIR/native-macos/Info.plist" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

swift "$ROOT_DIR/scripts/generate-app-icon.swift" "$ICON_MASTER_PNG"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"

find "$WEB_DIR" -type f \( -name "*.js" -o -name "*.css" -o -name "*.mask" \) -exec gzip -9 -n {} +

swiftc \
  -O \
  "$ROOT_DIR/native-macos/main.swift" \
  "$ROOT_DIR/native-macos/LocalHTTPServer.swift" \
  -framework AppKit \
  -framework WebKit \
  -framework Network \
  -o "$MACOS_DIR/$APP_NAME"

strip -x "$MACOS_DIR/$APP_NAME" || true

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "Built app: $APP_DIR"
echo "Built zip: $ZIP_PATH"
