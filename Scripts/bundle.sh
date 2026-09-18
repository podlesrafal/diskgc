#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
configuration="${1:-release}"
binary="$root/.build/$configuration/DiskGCBar"
app="$root/.build/DiskGC.app"

if [ ! -x "$binary" ]; then
    echo "missing $binary — run: swift build -c $configuration" >&2
    exit 1
fi

rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$binary" "$app/Contents/MacOS/DiskGCBar"

cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>DiskGC</string>
    <key>CFBundleDisplayName</key>
    <string>DiskGC</string>
    <key>CFBundleIdentifier</key>
    <string>dev.rpo.diskgc</string>
    <key>CFBundleExecutable</key>
    <string>DiskGCBar</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$app" >/dev/null 2>&1 || echo "warning: ad-hoc signing failed; notifications fall back to osascript" >&2

echo "$app"
