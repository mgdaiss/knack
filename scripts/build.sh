#!/usr/bin/env bash
# Builds, signs, notarizes and staples a Developer ID release of Knack.
#
#   DEVELOPMENT_TEAM=ABCDE12345 NOTARY_PROFILE=knack-notary scripts/build.sh
#
# One-time setup for notarization (stores an app-specific password in your keychain):
#   xcrun notarytool store-credentials knack-notary --apple-id you@example.com --team-id ABCDE12345
# Leave NOTARY_PROFILE unset to skip notarization (e.g. for a local smoke build).
#
# Needs Xcode 16+ and XcodeGen (brew install xcodegen).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT="$APP_DIR/build"
TEAM="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple team ID}"
PROFILE="${NOTARY_PROFILE:-}"

cd "$APP_DIR"
xcodegen generate --quiet

echo "==> Unit tests (KnackCore)"
(cd KnackCore && swift test)

echo "==> Archive"
rm -rf "$OUT"
xcodebuild archive -quiet \
  -project Knack.xcodeproj \
  -scheme Knack \
  -configuration Release \
  -archivePath "$OUT/Knack.xcarchive" \
  DEVELOPMENT_TEAM="$TEAM"

cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM</string>
  <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Export"
xcodebuild -exportArchive \
  -archivePath "$OUT/Knack.xcarchive" \
  -exportOptionsPlist "$OUT/ExportOptions.plist" \
  -exportPath "$OUT/export"

APP="$OUT/export/Knack.app"
codesign --verify --deep --strict --verbose=2 "$APP"

if [[ -n "$PROFILE" ]]; then
  echo "==> Notarize"
  ditto -c -k --keepParent "$APP" "$OUT/Knack-notarize.zip"
  xcrun notarytool submit "$OUT/Knack-notarize.zip" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$APP"
  spctl --assess --type execute --verbose "$APP"
else
  echo "==> Skipping notarization (NOTARY_PROFILE not set)"
fi

echo "==> Package"
ditto -c -k --keepParent "$APP" "$OUT/Knack.zip"
hdiutil create -quiet -volname Knack -srcfolder "$APP" -ov -format UDZO "$OUT/Knack.dmg"
if [[ -n "$PROFILE" ]]; then
  xcrun notarytool submit "$OUT/Knack.dmg" --keychain-profile "$PROFILE" --wait
  xcrun stapler staple "$OUT/Knack.dmg"
fi

echo "Built: $OUT/Knack.dmg"
