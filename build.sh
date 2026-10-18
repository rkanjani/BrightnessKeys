#!/bin/zsh
# Builds BrightnessKeys.app and installs it to ~/Applications.
set -e
cd "$(dirname "$0")"
APP=build/BrightnessKeys.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/BrightnessKeys"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.rohankanjani.BrightnessKeys</string>
  <key>CFBundleName</key><string>BrightnessKeys</string>
  <key>CFBundleExecutable</key><string>BrightnessKeys</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --identifier com.rohankanjani.BrightnessKeys "$APP"
if [[ "$1" == "--install" ]]; then
  mkdir -p ~/Applications
  rm -rf ~/Applications/BrightnessKeys.app
  cp -R "$APP" ~/Applications/
  echo "Installed to ~/Applications/BrightnessKeys.app"
fi
