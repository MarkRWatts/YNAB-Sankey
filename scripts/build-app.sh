#!/bin/bash
# Builds a release YNAB Sankey.app into ./build (ad-hoc signed).
# Usage: scripts/build-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
[ -f Resources/AppIcon.icns ] || swift scripts/make-icon.swift

APP="build/YNAB Sankey.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/YNABSankey" "$APP/Contents/MacOS/YNABSankey"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>YNAB Sankey</string>
    <key>CFBundleDisplayName</key><string>YNAB Sankey</string>
    <key>CFBundleIdentifier</key><string>com.markrwatts.YNABSankey</string>
    <key>CFBundleExecutable</key><string>YNABSankey</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "${1:-}" = "--install" ]; then
    rm -rf "/Applications/YNAB Sankey.app"
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/YNAB Sankey.app"
fi
