#!/bin/bash
set -e

# Create .app bundle for MediaSnag
# Usage: create_app.sh <install_dir>

INSTALL_DIR="${1:-$HOME/Library/ytdlp}"
APP_PATH="/Applications/MediaSnag.app"
CONTENTS="$APP_PATH/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"

echo "  创建 $APP_PATH ..."

# Remove old app if exists
if [ -d "$APP_PATH" ]; then
    rm -rf "$APP_PATH"
fi

# Create directory structure
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Create Info.plist
cat > "$CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>launcher</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleIdentifier</key>
    <string>com.mediasnag.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MediaSnag</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>4.0</string>
    <key>CFBundleVersion</key>
    <string>4.0.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key>
            <string>MediaSnag URL</string>
            <key>CFBundleURLSchemes</key>
            <array>
                <string>ytdl</string>
                <string>ytdla</string>
            </array>
        </dict>
    </array>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Create launcher executable
cat > "$MACOS_DIR/launcher" << 'LAUNCHER'
#!/bin/bash
INSTALL_DIR="$HOME/Library/ytdlp"
PYTHON="$INSTALL_DIR/bin/python3"

if [ ! -x "$PYTHON" ]; then
    PYTHON="$(which python3 2>/dev/null)"
fi

if [ -z "$PYTHON" ]; then
    osascript -e 'display alert "MediaSnag" message "Python 3 not found. Please re-run the installer."' 2>/dev/null
    exit 1
fi

export PYTHONPATH="$INSTALL_DIR/bin:$PYTHONPATH"

if [ -n "$1" ]; then
    exec "$PYTHON" -c "
import sys
sys.path.insert(0, '$INSTALL_DIR/bin')
from app.__main__ import main
sys.argv = ['mediasnag', '$1']
main()
"
else
    exec "$PYTHON" -c "
import sys
sys.path.insert(0, '$INSTALL_DIR/bin')
from app.__main__ import main
sys.argv = ['mediasnag']
main()
"
fi
LAUNCHER
chmod +x "$MACOS_DIR/launcher"

# Create PkgInfo
echo -n "APPL?????" > "$CONTENTS/PkgInfo"

# Copy icon if available
ICON_SOURCE="$(dirname "$0")/icon.icns"
if [ -f "$ICON_SOURCE" ]; then
    cp "$ICON_SOURCE" "$RESOURCES_DIR/icon.icns"
fi

# Clear quarantine attributes
xattr -cr "$APP_PATH" 2>/dev/null || true

echo "  .app bundle 创建完成: $APP_PATH"
