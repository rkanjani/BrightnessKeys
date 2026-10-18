#!/bin/zsh
# Builds build/BrightnessKeys.app.
#   ./build.sh             ad-hoc signed local build
#   ./build.sh --install   ...and copy it to ~/Applications
# Environment:
#   VERSION=1.0.0          marketing version (default below)
#   SIGN_IDENTITY="Developer ID Application: ..."   sign for distribution (hardened runtime + timestamp)
set -e
cd "$(dirname "$0")"

VERSION=${VERSION:-1.0.0}
BUILD_NUMBER=${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}
APP=build/BrightnessKeys.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/BrightnessKeys"

# App icon (.icns) from the 1024px master.
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.rohankanjani.BrightnessKeys</string>
  <key>CFBundleName</key><string>BrightnessKeys</string>
  <key>CFBundleDisplayName</key><string>BrightnessKeys</string>
  <key>CFBundleExecutable</key><string>BrightnessKeys</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Rohan Kanjani. MIT License.</string>
</dict></plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - --identifier com.rohankanjani.BrightnessKeys "$APP"
fi

if [[ "$1" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/BrightnessKeys.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/BrightnessKeys.app"
fi
