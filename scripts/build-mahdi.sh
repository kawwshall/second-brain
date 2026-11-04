#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/tools/mahdi"
DEST="${MAHDI_INSTALL_DIR:-$ROOT/dist}"
APP="$DEST/Mahdi.app"
swift build -c release --product Mahdi --package-path "$PACKAGE"
BIN_DIR="$(swift build -c release --show-bin-path --package-path "$PACKAGE")"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Mahdi" "$APP/Contents/MacOS/Mahdi"
cp "$PACKAGE/Assets/Mahdi.icns" "$APP/Contents/Resources/Mahdi.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Mahdi</string>
<key>CFBundleIdentifier</key><string>local.kaushal.secondbrainlaps</string>
<key>CFBundleName</key><string>Mahdi</string>
<key>CFBundleDisplayName</key><string>Mahdi</string>
<key>CFBundleIconFile</key><string>Mahdi.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>4</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$DEST/Mahdi.zip"
printf 'Built %s\n' "$APP"
