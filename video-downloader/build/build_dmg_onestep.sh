#!/bin/bash
set -e

# 一键构建 DMG 安装包（macOS）
# 自动下载依赖、组装负载、创建 DMG
# 生成的 DMG 包含一键安装器，双击即可完成全部配置

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/versions.env" 2>/dev/null || true

DOWNLOADS="$SCRIPT_DIR/downloads"
DMG_OUTPUT="$PROJECT_DIR/MediaSnag.dmg"
DMG_STAGING="$SCRIPT_DIR/dmg-staging"

echo "========================================="
echo "  一键构建 DMG 安装包"
echo "========================================="
echo ""

# --- Step 1: Download dependencies ---
echo "[1/6] 下载依赖..."
mkdir -p "$DOWNLOADS"

# Detect architecture
ARCH=$(uname -m)
if [ "$ARCH" = "arm64" ] || [ "$ARCH" = "aarch64" ]; then
    ARCH_LABEL="arm64"
    PYTHON_ARCH="aarch64"
else
    ARCH_LABEL="x86_64"
    PYTHON_ARCH="x86_64"
fi
echo "  构建架构: $ARCH_LABEL"

# Download ffmpeg for macOS (architecture-specific)
FFMPEG_READY=false
if [ "$ARCH_LABEL" = "arm64" ]; then
    # arm64: prefer Homebrew's ffmpeg (native arm64)
    if command -v brew &>/dev/null; then
        BREW_PREFIX="$(brew --prefix)"
        if [ -x "$BREW_PREFIX/bin/ffmpeg" ]; then
            echo "  打包 Homebrew arm64 ffmpeg + 依赖库..."
            FFMPEG_STAGING="$DOWNLOADS/ffmpeg-arm64"
            chmod -R u+w "$FFMPEG_STAGING" 2>/dev/null || true
            rm -rf "$FFMPEG_STAGING"
            mkdir -p "$FFMPEG_STAGING"

            # Copy ffmpeg and ffprobe binaries
            cp "$BREW_PREFIX/bin/ffmpeg" "$FFMPEG_STAGING/ffmpeg"
            cp "$BREW_PREFIX/bin/ffprobe" "$FFMPEG_STAGING/ffprobe" 2>/dev/null || true
            chmod u+w "$FFMPEG_STAGING/ffmpeg" "$FFMPEG_STAGING/ffprobe" 2>/dev/null || true

            # Recursively collect ALL dylib dependencies (including transitive)
            ALL_DYLIBS=""
            SEEN=""
            QUEUE=$(otool -L "$BREW_PREFIX/bin/ffmpeg" | grep "$BREW_PREFIX" | awk '{print $1}')
            while [ -n "$QUEUE" ]; do
                NEXT_QUEUE=""
                for dylib in $QUEUE; do
                    case "$SEEN" in *" $dylib "*) continue ;; esac
                    SEEN="$SEEN $dylib "
                    ALL_DYLIBS="$ALL_DYLIBS $dylib"
                    if [ -f "$dylib" ]; then
                        SUB=$(otool -L "$dylib" | grep "$BREW_PREFIX" | awk '{print $1}')
                        NEXT_QUEUE="$NEXT_QUEUE $SUB"
                    fi
                done
                QUEUE="$NEXT_QUEUE"
            done

            # Copy all collected dylibs (resolve symlinks, ensure writable)
            for dylib in $ALL_DYLIBS; do
                if [ -f "$dylib" ]; then
                    REAL_DYLIB=$(python3 -c "import os; print(os.path.realpath('$dylib'))" 2>/dev/null || echo "$dylib")
                    DYLIB_NAME=$(basename "$REAL_DYLIB")
                    cp -fL "$dylib" "$FFMPEG_STAGING/$DYLIB_NAME" 2>/dev/null || true
                    chmod u+w "$FFMPEG_STAGING/$DYLIB_NAME" 2>/dev/null || true
                fi
            done

            # Fix ffmpeg/ffprobe: change all dylib refs to @loader_path
            for dylib in $ALL_DYLIBS; do
                DYLIB_NAME=$(basename "$(python3 -c "import os; print(os.path.realpath('$dylib'))" 2>/dev/null || echo "$dylib")")
                install_name_tool -change "$dylib" "@loader_path/$DYLIB_NAME" "$FFMPEG_STAGING/ffmpeg" 2>/dev/null || true
                install_name_tool -change "$dylib" "@loader_path/$DYLIB_NAME" "$FFMPEG_STAGING/ffprobe" 2>/dev/null || true
            done

            # Fix inter-dylib references too
            for f in "$FFMPEG_STAGING"/*.dylib; do
                [ -f "$f" ] || continue
                for dylib in $ALL_DYLIBS; do
                    DYLIB_NAME=$(basename "$(python3 -c "import os; print(os.path.realpath('$dylib'))" 2>/dev/null || echo "$dylib")")
                    install_name_tool -change "$dylib" "@loader_path/$DYLIB_NAME" "$f" 2>/dev/null || true
                done
            done

            # Re-sign all modified binaries (install_name_tool invalidates signatures)
            codesign --force --sign - "$FFMPEG_STAGING/ffmpeg" 2>/dev/null || true
            [ -f "$FFMPEG_STAGING/ffprobe" ] && codesign --force --sign - "$FFMPEG_STAGING/ffprobe" 2>/dev/null || true
            for f in "$FFMPEG_STAGING"/*.dylib; do
                [ -f "$f" ] && codesign --force --sign - "$f" 2>/dev/null || true
            done

            chmod +x "$FFMPEG_STAGING/ffmpeg" "$FFMPEG_STAGING/ffprobe" 2>/dev/null || true
            echo "  ffmpeg + $(ls "$FFMPEG_STAGING"/*.dylib 2>/dev/null | wc -l | tr -d ' ') 个依赖库: OK"
            FFMPEG_READY=true
        fi
    fi
    if [ "$FFMPEG_READY" = false ]; then
        echo "  ⚠️  arm64 ffmpeg 需要 Homebrew 提供。请先运行: brew install ffmpeg"
        echo "  回退使用 x86_64 ffmpeg (需要 Rosetta 2)"
        if [ ! -f "$DOWNLOADS/ffmpeg.zip" ]; then
            curl -sL "https://evermeet.cx/ffmpeg/getrelease/zip" -o "$DOWNLOADS/ffmpeg.zip"
            curl -sL "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o "$DOWNLOADS/ffprobe.zip"
        fi
    fi
else
    if [ ! -f "$DOWNLOADS/ffmpeg.zip" ]; then
        echo "  下载 ffmpeg (x86_64)..."
        curl -sL "https://evermeet.cx/ffmpeg/getrelease/zip" -o "$DOWNLOADS/ffmpeg.zip"
        curl -sL "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip" -o "$DOWNLOADS/ffprobe.zip"
    fi
fi

# Download yt-dlp binary
if [ ! -f "$DOWNLOADS/yt-dlp_macos" ]; then
    echo "  下载 yt-dlp..."
    curl -sL "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" -o "$DOWNLOADS/yt-dlp_macos"
    chmod +x "$DOWNLOADS/yt-dlp_macos"
fi

# Download bundled Python (python-build-standalone) - architecture-specific
PYTHON_TAR="$DOWNLOADS/cpython-3.12.7+20241016-${PYTHON_ARCH}-apple-darwin-install_only.tar.gz"
if [ ! -f "$PYTHON_TAR" ]; then
    echo "  下载 bundled Python 3.12 ($ARCH_LABEL)..."
    curl -sL "https://github.com/indygreg/python-build-standalone/releases/download/20241016/cpython-3.12.7+20241016-${PYTHON_ARCH}-apple-darwin-install_only.tar.gz" -o "$PYTHON_TAR"
fi

echo "  依赖: OK"

# --- Step 2: Prepare staging ---
echo "[2/6] 准备安装包内容..."
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# --- Step 3: Create auto-installer .app ---
echo "[3/6] 创建自动安装器..."

INSTALLER_APP="$DMG_STAGING/Install MediaSnag.app"
INSTALLER_CONTENTS="$INSTALLER_APP/Contents"
mkdir -p "$INSTALLER_CONTENTS/MacOS"
mkdir -p "$INSTALLER_CONTENTS/Resources"

# Info.plist for installer app
cat > "$INSTALLER_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>install</string>
    <key>CFBundleIdentifier</key>
    <string>com.mediasnag.installer</string>
    <key>CFBundleName</key>
    <string>Install MediaSnag</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>4.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

# Installer executable (bash script)
cat > "$INSTALLER_CONTENTS/MacOS/install" << 'INSTALLER'
#!/bin/bash
INSTALL_DIR="$HOME/Library/ytdlp"
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
RESOURCES="$SCRIPT_DIR/Contents/Resources"

# Show progress dialog
osascript -e 'display notification "正在安装 MediaSnag..." with title "Install MediaSnag"' 2>/dev/null

# Create directories
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/userscript"
mkdir -p "$INSTALL_DIR/source"
mkdir -p "$INSTALL_DIR/data"

# Copy bundled Python
if [ -d "$RESOURCES/python" ]; then
    rm -rf "$INSTALL_DIR/python"
    cp -R "$RESOURCES/python" "$INSTALL_DIR/"
    chmod -R +x "$INSTALL_DIR/python/bin/"
fi

BUNDLED_PYTHON="$INSTALL_DIR/python/bin/python3.12"
SITE_PACKAGES="$INSTALL_DIR/python/lib/python3.12/site-packages"

# Install yt-dlp Python package if not already installed
if [ -f "$RESOURCES/yt-dlp-python.tar.gz" ]; then
    tar -xzf "$RESOURCES/yt-dlp-python.tar.gz" -C "$INSTALL_DIR/source/"
fi

# Copy app source (preserve app/ package structure)
if [ -d "$RESOURCES/app" ]; then
    rm -rf "$INSTALL_DIR/bin/app"
    cp -R "$RESOURCES/app" "$INSTALL_DIR/bin/"
fi

# Copy userscript
if [ -f "$RESOURCES/universal_downloader.user.js" ]; then
    cp "$RESOURCES/universal_downloader.user.js" "$INSTALL_DIR/userscript/"
fi

# Copy ffmpeg if bundled
if [ -f "$RESOURCES/ffmpeg" ]; then
    cp "$RESOURCES/ffmpeg" "$INSTALL_DIR/bin/"
    chmod +x "$INSTALL_DIR/bin/ffmpeg"
fi
if [ -f "$RESOURCES/ffprobe" ]; then
    cp "$RESOURCES/ffprobe" "$INSTALL_DIR/bin/"
    chmod +x "$INSTALL_DIR/bin/ffprobe"
fi
# Copy bundled dylibs (for Homebrew-sourced ffmpeg)
for dylib in "$RESOURCES"/*.dylib; do
    [ -f "$dylib" ] && cp "$dylib" "$INSTALL_DIR/bin/"
done

# Copy yt-dlp binary if bundled
if [ -f "$RESOURCES/yt-dlp" ]; then
    cp "$RESOURCES/yt-dlp" "$INSTALL_DIR/bin/"
    chmod +x "$INSTALL_DIR/bin/yt-dlp"
fi

# Create .app for MediaSnag
APP_PATH="/Applications/MediaSnag.app"
APP_CONTENTS="$APP_PATH/Contents"

# Create AppleScript source
cat > /tmp/mediasnag_launcher.applescript << 'APPLESCRIPT'
on open location theURL
    my handleURL:theURL
end open location

on run
    set homeDir to POSIX path of (path to home folder)
    set installDir to homeDir & "Library/ytdlp/"
    set pythonPath to installDir & "python/bin/python3.12"
    set sitePackages to installDir & "python/lib/python3.12/site-packages"
    set appDir to installDir & "bin"

    set args to arguments of current application
    if (count of args) > 0 then
        set firstArg to item 1 of args
        if firstArg starts with "ytdl://" or firstArg starts with "ytdla://" then
            my handleURL:firstArg
            return
        end if
    end if

    set pythonCode to "import sys; sys.path.insert(0, '" & appDir & "'); sys.path.insert(0, '" & sitePackages & "'); from app.__main__ import main; sys.argv=['mediasnag', '--serve']; main()"
    do shell script pythonPath & " -c " & quoted form of pythonCode & " &"
end run

on handleURL:theURL
    set homeDir to POSIX path of (path to home folder)
    set installDir to homeDir & "Library/ytdlp/"
    set pythonPath to installDir & "python/bin/python3.12"
    set sitePackages to installDir & "python/lib/python3.12/site-packages"
    set appDir to installDir & "bin"
    activate
    set pythonCode to "import sys,os; sys.path.insert(0, '" & appDir & "'); sys.path.insert(0, '" & sitePackages & "'); from app.__main__ import main; sys.argv=['mediasnag', os.environ['MEDIASNAG_URL']]; main()"
    do shell script "MEDIASNAG_URL=" & quoted form of theURL & " " & pythonPath & " -c " & quoted form of pythonCode & " &"
end handleURL
APPLESCRIPT

# Create proper AppleScript app bundle
osacompile -o "$APP_PATH" /tmp/mediasnag_launcher.applescript 2>/dev/null
rm /tmp/mediasnag_launcher.applescript

# Update Info.plist with URL schemes and settings
cat > "$APP_CONTENTS/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>applet</string>
    <key>CFBundleIdentifier</key>
    <string>com.mediasnag.app</string>
    <key>CFBundleName</key>
    <string>MediaSnag</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>4.0</string>
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
</dict>
</plist>
PLIST

# Register URL scheme
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true

# Clear quarantine
xattr -cr "$APP_PATH" 2>/dev/null || true
xattr -cr "$INSTALL_DIR" 2>/dev/null || true

# Open userscript on GitHub for Tampermonkey installation
SCRIPT_URL="https://raw.githubusercontent.com/347ssq/MediaSnag/main/universal_downloader.user.js"
osascript -e 'display notification "安装完成！正在打开脚本安装页面..." with title "MediaSnag" sound name "Glass"' 2>/dev/null
open -a Safari "$SCRIPT_URL"

osascript -e 'display dialog "MediaSnag 安装完成！\n\n已安装到 /Applications/MediaSnag.app\n\n浏览器已打开脚本文件，请在 Tampermonkey 中确认安装。" buttons {"好的"} default button "好的" with title "安装完成"' 2>/dev/null
INSTALLER
chmod +x "$INSTALLER_CONTENTS/MacOS/install"

# --- Step 4: Copy resources into installer ---
echo "[4/6] 打包资源..."
mkdir -p "$INSTALLER_CONTENTS/Resources"

# Copy app code
cp -R "$PROJECT_DIR/app" "$INSTALLER_CONTENTS/Resources/app"
cp "$PROJECT_DIR/userscript/universal_downloader.user.js" "$INSTALLER_CONTENTS/Resources/"

# Copy ffmpeg (architecture-specific)
if [ -d "$DOWNLOADS/ffmpeg-arm64" ] && [ -f "$DOWNLOADS/ffmpeg-arm64/ffmpeg" ]; then
    cp "$DOWNLOADS/ffmpeg-arm64/ffmpeg" "$INSTALLER_CONTENTS/Resources/ffmpeg"
    [ -f "$DOWNLOADS/ffmpeg-arm64/ffprobe" ] && cp "$DOWNLOADS/ffmpeg-arm64/ffprobe" "$INSTALLER_CONTENTS/Resources/ffprobe"
    # Copy all bundled dylibs
    for dylib in "$DOWNLOADS/ffmpeg-arm64"/*.dylib; do
        [ -f "$dylib" ] && cp "$dylib" "$INSTALLER_CONTENTS/Resources/"
    done
elif [ -f "$DOWNLOADS/ffmpeg.zip" ]; then
    unzip -q -o "$DOWNLOADS/ffmpeg.zip" -d "$INSTALLER_CONTENTS/Resources/"
fi
if [ -f "$DOWNLOADS/ffprobe.zip" ] && [ ! -f "$INSTALLER_CONTENTS/Resources/ffprobe" ]; then
    unzip -q -o "$DOWNLOADS/ffprobe.zip" -d "$INSTALLER_CONTENTS/Resources/"
fi

# Copy yt-dlp binary
if [ -f "$DOWNLOADS/yt-dlp_macos" ]; then
    cp "$DOWNLOADS/yt-dlp_macos" "$INSTALLER_CONTENTS/Resources/yt-dlp"
fi

# Copy bundled Python
echo "  解压 bundled Python..."
PYTHON_STAGING="$DOWNLOADS/python-staging"
rm -rf "$PYTHON_STAGING"
mkdir -p "$PYTHON_STAGING"
tar -xzf "$PYTHON_TAR" -C "$PYTHON_STAGING"
# The tarball extracts to a "python" directory
if [ -d "$PYTHON_STAGING/python" ]; then
    cp -R "$PYTHON_STAGING/python" "$INSTALLER_CONTENTS/Resources/python"
else
    echo "  警告: bundled Python 解压失败"
fi
rm -rf "$PYTHON_STAGING"

# Install yt-dlp into bundled Python's site-packages for distribution
echo "  安装 yt-dlp Python 包..."
RESOURCES_PYTHON="$INSTALLER_CONTENTS/Resources/python/bin/python3.12"
if [ -f "$RESOURCES_PYTHON" ]; then
    "$RESOURCES_PYTHON" -m pip install --quiet --target "$DOWNLOADS/yt-dlp-pkg" yt-dlp 2>/dev/null
    # Package as tarball for the installer to extract
    tar -czf "$INSTALLER_CONTENTS/Resources/yt-dlp-python.tar.gz" -C "$DOWNLOADS/yt-dlp-pkg" .
    rm -rf "$DOWNLOADS/yt-dlp-pkg"
    echo "  yt-dlp Python 包: OK"
else
    echo "  警告: bundled Python 不可用，跳过 yt-dlp 安装"
fi

# Clear quarantine on installer
xattr -cr "$INSTALLER_APP" 2>/dev/null || true

# --- Step 5: Add README ---
echo "[5/6] 添加说明文档..."
cat > "$DMG_STAGING/使用说明.txt" << 'README'
MediaSnag v4.0 - 安装说明
============================

安装步骤:
  1. 双击 "Install MediaSnag.app"
  2. 等待安装完成，浏览器会自动打开
  3. 在浏览器中安装 Tampermonkey 脚本

安装完成后:
  - MediaSnag.app 会安装到 /Applications/
  - 支持 ytdl:// 和 ytdla:// URL Scheme
  - 下载文件保存到 ~/Downloads/

系统要求:
  - macOS 10.15 或更高版本
  - 无需额外安装 Python（已内置）
README

# --- Step 6: Create DMG ---
echo "[6/6] 创建 DMG..."
rm -f "$DMG_OUTPUT"
hdiutil create -volname "MediaSnag" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

rm -rf "$DMG_STAGING"

echo ""
echo "========================================="
echo "  DMG 构建完成!"
echo "========================================="
echo ""
ls -lh "$DMG_OUTPUT"
echo ""
echo "使用方法:"
echo "  1. 双击打开 $DMG_OUTPUT"
echo "  2. 双击 'Install MediaSnag.app'"
echo "  3. 自动完成安装并打开浏览器"
echo ""

# Auto-mount the DMG (use hdiutil instead of open to avoid file association issues)
hdiutil attach "$DMG_OUTPUT" -nobrowse
