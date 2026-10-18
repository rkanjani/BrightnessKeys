#!/bin/zsh
# Archives, signs with Developer ID, notarizes, staples, and publishes a GitHub release.
#   ./release.sh 1.0.0
# Requires Xcode signed in to the team's Apple developer account (Xcode → Settings → Accounts).
# Signing and notarization go through that session, so no passwords or API keys are needed.
# Environment:
#   SKIP_PUBLISH=1   stop after producing the notarized zip
set -e
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version>}
BUILD_NUMBER=$(git rev-list --count HEAD)
ARCHIVE=build/BrightnessKeys-$VERSION.xcarchive
APP=build/notarized/BrightnessKeys.app
ZIP=build/BrightnessKeys-$VERSION.zip

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }

rm -rf "$ARCHIVE" build/export build/notarized
xcodebuild -project BrightnessKeys.xcodeproj -scheme BrightnessKeys -configuration Release \
  -destination 'generic/platform=macOS' -archivePath "$ARCHIVE" -allowProvisioningUpdates \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

# Signs with Developer ID and uploads to Apple's notary service.
xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportPath build/export \
  -exportOptionsPlist Resources/ExportOptions.plist -allowProvisioningUpdates

echo "Waiting for notarization..."
until xcodebuild -exportNotarizedApp -archivePath "$ARCHIVE" -exportPath build/notarized 2>build/notarize.log; do
  grep -q "is processing" build/notarize.log || { cat build/notarize.log; exit 1; }
  sleep 30
done

codesign --verify --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"

rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Notarized build: $ZIP"
[[ -n "$SKIP_PUBLISH" ]] && exit 0

git tag -a "v$VERSION" -m "BrightnessKeys $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$ZIP" --title "BrightnessKeys $VERSION" --notes-file - <<NOTES
Brightness keys now adjust **the display your pointer is on**: your external monitor over DDC/CI, or your Mac's own screen as usual.

## Install

1. Download **BrightnessKeys-$VERSION.zip** below and unzip it.
2. Drag **BrightnessKeys.app** to your Applications folder and open it.
3. Allow BrightnessKeys in **System Settings → Privacy & Security → Accessibility** so it can catch the brightness keys.

Signed with Developer ID and notarized by Apple. Requires macOS 14+ on Apple silicon.

BrightnessKeys is free and open source under the MIT license.
NOTES
