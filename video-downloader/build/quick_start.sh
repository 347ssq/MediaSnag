#!/bin/bash
set -e

# 一键构建并启动 MediaSnag（macOS）
# 自动检测/下载依赖，组装负载，启动服务器

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/versions.env" 2>/dev/null || true

DOWNLOADS="$SCRIPT_DIR/downloads"
INSTALL_DIR="$HOME/Library/ytdlp"

echo "========================================="
echo "  MediaSnag - 一键构建启动"
echo "========================================="
echo ""

# --- Step 1: Check Python ---
echo "[1/4] 检查 Python 环境..."
PYTHON="$(which python3)"
if [ -z "$PYTHON" ]; then
    echo "错误: 未找到 python3"
    exit 1
fi
echo "  Python: $PYTHON ($($PYTHON --version))"

# --- Step 2: Check yt-dlp ---
echo "[2/4] 检查 yt-dlp..."
if ! $PYTHON -c "import yt_dlp" 2>/dev/null; then
    echo "  安装 yt-dlp Python 包..."
    $PYTHON -m pip install --user yt-dlp 2>/dev/null || \
    $PYTHON -m pip install yt-dlp
fi
echo "  yt-dlp: OK"

# --- Step 3: Check ffmpeg ---
echo "[3/4] 检查 ffmpeg..."
FFMPEG=""
if command -v ffmpeg &>/dev/null; then
    FFMPEG="$(which ffmpeg)"
elif [ -x "$INSTALL_DIR/bin/ffmpeg" ]; then
    FFMPEG="$INSTALL_DIR/bin/ffmpeg"
elif [ -x "$HOME/Library/Python/3.9/bin/static_ffmpeg" ]; then
    FFMPEG="$HOME/Library/Python/3.9/bin/static_ffmpeg"
fi

if [ -n "$FFMPEG" ]; then
    echo "  ffmpeg: $FFMPEG"
else
    echo "  未找到 ffmpeg，尝试自动下载..."
    mkdir -p "$INSTALL_DIR/bin"
    ARCH="$(uname -m)"
    if [ "$ARCH" = "arm64" ]; then
        curl -sL "https://evermeet.cx/ffmpeg/getrelease/zip" -o /tmp/ffmpeg.zip
    else
        curl -sL "https://evermeet.cx/ffmpeg/getrelease/zip" -o /tmp/ffmpeg.zip
    fi
    if [ -f /tmp/ffmpeg.zip ]; then
        unzip -q -o /tmp/ffmpeg.zip -d "$INSTALL_DIR/bin/"
        chmod +x "$INSTALL_DIR/bin/ffmpeg" "$INSTALL_DIR/bin/ffprobe" 2>/dev/null
        FFMPEG="$INSTALL_DIR/bin/ffmpeg"
        rm -f /tmp/ffmpeg.zip
        echo "  ffmpeg: 已下载到 $INSTALL_DIR/bin/"
    else
        echo "  警告: ffmpeg 下载失败，视频合并功能可能不可用"
    fi
fi

# --- Step 4: Setup install directory & launch ---
echo "[4/4] 启动 MediaSnag..."
echo ""

# Create install dir and copy app
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/userscript"
cp -R "$PROJECT_DIR/app/"* "$INSTALL_DIR/bin/"
cp "$PROJECT_DIR/userscript/universal_downloader.user.js" "$INSTALL_DIR/userscript/"

# Create .app bundle
bash "$PROJECT_DIR/installer/macos/create_app.sh" "$INSTALL_DIR" 2>/dev/null || true

# Register URL scheme
APP_PATH="/Applications/MediaSnag.app"
if [ -d "$APP_PATH" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true
fi

# Set PYTHONPATH and launch
export PYTHONPATH="$INSTALL_DIR/bin:$PYTHONPATH"

# Find available port
PORT=19527
for p in $(seq 19527 19537); do
    if ! lsof -i :$p >/dev/null 2>&1; then
        PORT=$p
        break
    fi
done

echo "========================================="
echo "  MediaSnag 已启动!"
echo "========================================="
echo ""
echo "  本地地址: http://127.0.0.1:$PORT"
echo "  脚本安装: http://127.0.0.1:$PORT/userscript.user.js"
echo ""
echo "  按 Ctrl+C 停止服务器"
echo ""

# Open browser
sleep 1
open "http://127.0.0.1:$PORT/"
sleep 0.5
open "http://127.0.0.1:$PORT/userscript.user.js"

# Run server (blocking)
exec $PYTHON -m app
