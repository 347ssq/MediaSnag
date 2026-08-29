#!/bin/bash
set -e

# Fetch all platform dependencies for the MediaSnag package.
# Run on macOS. Downloads Python standalone, yt-dlp, and ffmpeg for each platform.
# Output goes to build/downloads/

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/versions.env"

DOWNLOADS="$SCRIPT_DIR/downloads"
mkdir -p "$DOWNLOADS"

download() {
    local url="$1"
    local dest="$2"
    if [ -f "$dest" ]; then
        echo "  已存在: $(basename "$dest")"
        return
    fi
    echo "  下载: $(basename "$dest")"
    curl -L -o "$dest" "$url"
}

echo "========================================="
echo "  下载平台依赖"
echo "========================================="

# --- macOS arm64 ---
echo ""
echo "[macOS arm64]"
mkdir -p "$DOWNLOADS/macos/arm64"
download "$PYTHON_MACOS_ARM64_URL" "$DOWNLOADS/macos/arm64/python.tar.gz"

# --- macOS x86_64 ---
echo ""
echo "[macOS x86_64]"
mkdir -p "$DOWNLOADS/macos/x86_64"
download "$PYTHON_MACOS_X86_64_URL" "$DOWNLOADS/macos/x86_64/python.tar.gz"

# --- macOS ffmpeg (universal) ---
echo ""
echo "[macOS ffmpeg]"
mkdir -p "$DOWNLOADS/macos/ffmpeg"
download "$FFMPEG_MACOS_URL" "$DOWNLOADS/macos/ffmpeg/ffmpeg.zip"
download "$FFMPEG_MACOS_FFPROBE_URL" "$DOWNLOADS/macos/ffmpeg/ffprobe.zip"

# --- Windows ---
echo ""
echo "[Windows]"
mkdir -p "$DOWNLOADS/windows"
download "$PYTHON_WINDOWS_URL" "$DOWNLOADS/windows/python.tar.gz"
download "$FFMPEG_WINDOWS_URL" "$DOWNLOADS/windows/ffmpeg.zip"

# --- Linux ---
echo ""
echo "[Linux]"
mkdir -p "$DOWNLOADS/linux"
download "$PYTHON_LINUX_URL" "$DOWNLOADS/linux/python.tar.gz"
download "$FFMPEG_LINUX_URL" "$DOWNLOADS/linux/ffmpeg.tar.xz"

# --- yt-dlp (universal binary) ---
echo ""
echo "[yt-dlp]"
mkdir -p "$DOWNLOADS/ytdlp"
download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos" "$DOWNLOADS/ytdlp/yt-dlp_macos"
download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" "$DOWNLOADS/ytdlp/yt-dlp.exe"
download "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp" "$DOWNLOADS/ytdlp/yt-dlp_linux"

# --- yt-dlp Python package (for import) ---
echo ""
echo "[yt-dlp Python package]"
mkdir -p "$DOWNLOADS/ytdlp_pkg"
if [ ! -d "$DOWNLOADS/ytdlp_pkg/yt_dlp" ]; then
    echo "  安装 yt-dlp Python 包..."
    pip3 download --no-deps --dest "$DOWNLOADS/ytdlp_pkg" "yt-dlp==$YTDLP_VERSION" 2>/dev/null || \
    pip3 download --no-deps --dest "$DOWNLOADS/ytdlp_pkg" yt-dlp 2>/dev/null || \
    echo "  警告: 无法下载 yt-dlp Python 包，将使用系统已安装版本"
fi

echo ""
echo "========================================="
echo "  下载完成!"
echo "========================================="
echo "  目录: $DOWNLOADS"
du -sh "$DOWNLOADS"/*
