#!/usr/bin/env bash
# Builds a Release archive of Knack and exports a Developer ID–signed app.
#
#   DEVELOPMENT_TEAM=ABCDE12345 scripts/build.sh
#
# Needs Xcode 16+ and XcodeGen (brew install xcodegen). Notarization is added in M6.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT/app"
OUT="$APP_DIR/build"
TEAM="${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your Apple team ID}"

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

echo "Built: $OUT/export/Knack.app"
