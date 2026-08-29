#!/bin/bash
set -e

# Create DMG distribution package for MediaSnag.
# Contains installers and payloads for all platforms.
# Output: build/MediaSnag.dmg

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PAYLOADS="$SCRIPT_DIR/payloads"

DMG_STAGING="$SCRIPT_DIR/dmg-staging"
DMG_OUTPUT="$SCRIPT_DIR/MediaSnag.dmg"
DMG_NAME="MediaSnag"
DMG_TEMP="$SCRIPT_DIR/dmg-temp"

echo "========================================="
echo "  创建 DMG 安装包"
echo "========================================="

# Clean previous build
rm -rf "$DMG_STAGING" "$DMG_TEMP" "$DMG_OUTPUT"
mkdir -p "$DMG_STAGING"

# Copy README
cat > "$DMG_STAGING/README.txt" << 'README'
MediaSnag - 全平台安装包
=========================

本安装包包含 macOS、Windows 和 Linux 的安装程序。

macOS 用户:
  双击 "Install MediaSnag.command" 即可自动安装。

Windows 用户:
  打开 windows 文件夹，双击 "install.bat"。

Linux 用户:
  打开 linux 文件夹，运行 "bash install.sh"。

安装完成后:
  - 浏览器中安装 Tampermonkey 脚本即可使用
  - 支持 ytdl:// 和 ytdla:// URL Scheme
  - 视频文件保存到系统 Downloads 文件夹

要求:
  - macOS 10.15+ / Windows 10+ / 现代 Linux 发行版
  - 无需额外安装 Python 或 ffmpeg（已内置）
README

# Create macOS installer launcher
cat > "$DMG_STAGING/Install MediaSnag.command" << 'MACINSTALL'
#!/bin/bash
cd "$(dirname "$0")"
echo "正在启动 macOS 安装程序..."
bash "macos/install.command"
MACINSTALL
chmod +x "$DMG_STAGING/Install MediaSnag.command"

# Copy macOS installer + payload
echo "复制 macOS 文件..."
mkdir -p "$DMG_STAGING/macos"
cp -R "$PROJECT_DIR/installer/macos/install.command" "$DMG_STAGING/macos/"
cp -R "$PROJECT_DIR/installer/macos/create_app.sh" "$DMG_STAGING/macos/"
# Copy app source for installer to use
cp -R "$PROJECT_DIR/app" "$DMG_STAGING/macos/app"

# Copy platform payloads if they exist
for platform in macos/arm64 macos/x86_64 windows linux; do
    if [ -f "$PAYLOADS/$platform/runtime.tar.gz" ]; then
        echo "复制 $platform 负载..."
        local_dir="$DMG_STAGING/$platform"
        mkdir -p "$local_dir"
        cp "$PAYLOADS/$platform/runtime.tar.gz" "$local_dir/"
    fi
done

# Copy Windows installer
echo "复制 Windows 文件..."
mkdir -p "$DMG_STAGING/windows"
cp "$PROJECT_DIR/installer/windows/install.bat" "$DMG_STAGING/windows/"
cp "$PROJECT_DIR/installer/windows/register_scheme.ps1" "$DMG_STAGING/windows/"

# Copy Linux installer
echo "复制 Linux 文件..."
mkdir -p "$DMG_STAGING/linux"
cp "$PROJECT_DIR/installer/linux/install.sh" "$DMG_STAGING/linux/"
cp "$PROJECT_DIR/installer/linux/ytdl-handler.desktop" "$DMG_STAGING/linux/"

# Create DMG
echo ""
echo "创建 DMG..."
hdiutil create -volname "$DMG_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$DMG_OUTPUT"

# Cleanup
rm -rf "$DMG_STAGING" "$DMG_TEMP"

echo ""
echo "========================================="
echo "  DMG 创建完成!"
echo "========================================="
ls -lh "$DMG_OUTPUT"
echo ""
echo "文件: $DMG_OUTPUT"
