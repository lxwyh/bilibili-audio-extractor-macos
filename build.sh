#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
OUTPUT_DIR="$SCRIPT_DIR/dist"
APP_NAME="B站字幕音频提取器.app"
APP_DIR="$OUTPUT_DIR/$APP_NAME"
ICON_DIR="$SCRIPT_DIR/build/AppIcon.iconset"
MODULE_CACHE="$SCRIPT_DIR/build/ModuleCache"
YTDLP_BIN="$SCRIPT_DIR/vendor/yt-dlp"

mkdir -p "$OUTPUT_DIR" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$ICON_DIR" "$MODULE_CACHE" "$SCRIPT_DIR/vendor"

if [[ ! -x "$YTDLP_BIN" ]]; then
  echo "Downloading the official yt-dlp macOS executable…"
  /usr/bin/curl -fL --retry 3 --connect-timeout 20 \
    -o "$YTDLP_BIN" \
    https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos
  /bin/chmod +x "$YTDLP_BIN"
fi

if [[ ! -f "$SCRIPT_DIR/build/AppIcon.icns" ]]; then
  /usr/bin/swift "$SCRIPT_DIR/make_icon.swift" "$ICON_DIR/icon_512x512@2x.png"
  /usr/bin/sips -z 16 16 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_16x16.png" >/dev/null
  /usr/bin/sips -z 32 32 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_16x16@2x.png" >/dev/null
  /usr/bin/sips -z 32 32 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_32x32.png" >/dev/null
  /usr/bin/sips -z 64 64 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_32x32@2x.png" >/dev/null
  /usr/bin/sips -z 128 128 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_128x128.png" >/dev/null
  /usr/bin/sips -z 256 256 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_128x128@2x.png" >/dev/null
  /usr/bin/sips -z 256 256 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_256x256.png" >/dev/null
  /usr/bin/sips -z 512 512 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_256x256@2x.png" >/dev/null
  /usr/bin/sips -z 512 512 "$ICON_DIR/icon_512x512@2x.png" --out "$ICON_DIR/icon_512x512.png" >/dev/null
  /usr/bin/iconutil -c icns "$ICON_DIR" -o "$SCRIPT_DIR/build/AppIcon.icns"
fi

/usr/bin/swiftc \
  -target arm64-apple-macosx13.0 \
  -module-cache-path "$MODULE_CACHE" \
  -swift-version 5 \
  -O \
  -framework AppKit \
  "$SCRIPT_DIR/App.swift" \
  -o "$APP_DIR/Contents/MacOS/BiliAudioExtractor"

/bin/cp "$SCRIPT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
/bin/cp "$YTDLP_BIN" "$APP_DIR/Contents/Resources/yt-dlp"
/bin/cp "$SCRIPT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
/bin/cp "$SCRIPT_DIR/build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/bin/chmod +x "$APP_DIR/Contents/MacOS/BiliAudioExtractor" "$APP_DIR/Contents/Resources/yt-dlp"

/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$OUTPUT_DIR/B站字幕音频提取器.zip"
/bin/cp "$SCRIPT_DIR/README.md" "$OUTPUT_DIR/使用说明.md"

echo "$APP_DIR"
