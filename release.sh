#!/bin/zsh
# Builds, signs with Developer ID, notarizes, staples, and publishes a GitHub release.
#   ./release.sh 1.0.0
# One-time setup:
#   - A "Developer ID Application" certificate in your keychain (Xcode → Settings → Accounts → Manage Certificates)
#   - xcrun notarytool store-credentials BrightnessKeys --apple-id <apple-id> --team-id <team-id>
# Environment:
#   NOTARY_PROFILE=BrightnessKeys   keychain profile created above
#   SKIP_PUBLISH=1                  stop after producing the notarized zip
set -e
cd "$(dirname "$0")"

VERSION=${1:?usage: ./release.sh <version>}
NOTARY_PROFILE=${NOTARY_PROFILE:-BrightnessKeys}
APP=build/BrightnessKeys.app
ZIP=build/BrightnessKeys-$VERSION.zip

[[ -z "$(git status --porcelain)" ]] || { echo "Commit your changes first."; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -1)
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application certificate found in the keychain."; exit 1; }
echo "Signing as: $IDENTITY"

VERSION=$VERSION SIGN_IDENTITY="$IDENTITY" ./build.sh
codesign --verify --strict --verbose=2 "$APP"

echo "Submitting for notarization (usually a few minutes)..."
rm -f build/notarize.zip
ditto -c -k --keepParent "$APP" build/notarize.zip
RESULT=$(xcrun notarytool submit build/notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait --output-format json)
STATUS=$(echo "$RESULT" | plutil -extract status raw -o - - 2>/dev/null || true)
if [[ "$STATUS" != "Accepted" ]]; then
  echo "Notarization failed: $RESULT"
  ID=$(echo "$RESULT" | plutil -extract id raw -o - - 2>/dev/null || true)
  [[ -n "$ID" ]] && xcrun notarytool log "$ID" --keychain-profile "$NOTARY_PROFILE"
  exit 1
fi

xcrun stapler staple "$APP"
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
