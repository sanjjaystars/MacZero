#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "==> Building MacZeroApp with Swift Package Manager..."
cd "${ROOT_DIR}"
swift build --target MacZeroApp

BIN_PATH="${ROOT_DIR}/.build/out/Products/Debug/MacZeroApp"
if [ ! -f "${BIN_PATH}" ]; then
    # Fallback search if path varies by arch
    BIN_PATH=$(find "${ROOT_DIR}/.build" -name "MacZeroApp" -type f -perm +111 | head -n 1)
fi

if [ -z "${BIN_PATH}" ] || [ ! -f "${BIN_PATH}" ]; then
    echo "Error: MacZeroApp binary not found." >&2
    exit 1
fi

APP_BUNDLE="${ROOT_DIR}/MacZero.app"
echo "==> Packaging into ${APP_BUNDLE}..."

rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${BIN_PATH}" "${APP_BUNDLE}/Contents/MacOS/MacZeroApp"
chmod +x "${APP_BUNDLE}/Contents/MacOS/MacZeroApp"

cat << 'EOF' > "${APP_BUNDLE}/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>MacZeroApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.maczero.MacZero</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacZero</string>
    <key>CFBundleDisplayName</key>
    <string>MacZero</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRequiresAquaSystemAppearance</key>
    <false/>
</dict>
</plist>
EOF

echo "==> Successfully created MacZero.app!"
echo "    Launch GUI directly with: open ${APP_BUNDLE}"
