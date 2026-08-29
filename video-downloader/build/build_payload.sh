#!/bin/bash
set -e

# Assemble platform-specific payloads for distribution.
# Each payload contains: Python standalone + yt-dlp + ffmpeg + app source.
# Output: build/payloads/<platform>/runtime.tar.gz

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/versions.env"

DOWNLOADS="$SCRIPT_DIR/downloads"
PAYLOADS="$SCRIPT_DIR/payloads"
mkdir -p "$PAYLOADS"

build_payload() {
    local platform="$1"    # e.g. macos/arm64
    local python_bin="$2"  # python3 binary name within extracted dir
    local ffmpeg_src="$3"  # path to ffmpeg archive
    local ytdlp_bin="$4"   # path to yt-dlp binary

    local staging="$PAYLOADS/$platform/staging"
    local bin_dir="$staging/bin"

    echo ""
    echo "[$platform] 组装负载..."

    rm -rf "$staging"
    mkdir -p "$bin_dir"

    # Extract Python standalone
    if [ -f "$DOWNLOADS/$platform/python.tar.gz" ]; then
        echo "  解压 Python..."
        tar -xzf "$DOWNLOADS/$platform/python.tar.gz" -C "$staging"
        # python-build-standalone extracts to python/ subdirectory
        if [ -d "$staging/python" ]; then
            mv "$staging/python/"* "$bin_dir/"
            rmdir "$staging/python"
        fi
    else
        echo "  警告: 未找到 Python 负载"
        return 1
    fi

    # Copy yt-dlp binary
    if [ -f "$ytdlp_bin" ]; then
        echo "  复制 yt-dlp..."
        cp "$ytdlp_bin" "$bin_dir/yt-dlp"
        chmod +x "$bin_dir/yt-dlp"
    fi

    # Copy ffmpeg
    if [ -n "$ffmpeg_src" ] && [ -f "$ffmpeg_src" ]; then
        echo "  解压 ffmpeg..."
        local ffmpeg_tmp="$PAYLOADS/$platform/ffmpeg_tmp"
        mkdir -p "$ffmpeg_tmp"
        case "$ffmpeg_src" in
            *.zip)
                unzip -q -o "$ffmpeg_src" -d "$ffmpeg_tmp"
                ;;
            *.tar.xz)
                tar -xJf "$ffmpeg_src" -C "$ffmpeg_tmp"
                ;;
        esac
        # Find and copy ffmpeg/ffprobe binaries
        find "$ffmpeg_tmp" -name "ffmpeg" -o -name "ffmpeg.exe" | head -1 | xargs -I{} cp {} "$bin_dir/"
        find "$ffmpeg_tmp" -name "ffprobe" -o -name "ffprobe.exe" | head -1 | xargs -I{} cp {} "$bin_dir/"
        chmod +x "$bin_dir/ffmpeg"* "$bin_dir/ffprobe"* 2>/dev/null || true
        rm -rf "$ffmpeg_tmp"
    fi

    # Copy app source
    echo "  复制应用源码..."
    cp -R "$PROJECT_DIR/app" "$bin_dir/app"

    # Copy userscript
    mkdir -p "$staging/userscript"
    cp "$PROJECT_DIR/userscript/universal_downloader.user.js" "$staging/userscript/"

    # Install yt-dlp Python package into bundled Python
    local py_path="$bin_dir/$python_bin"
    if [ -x "$py_path" ] && [ -d "$DOWNLOADS/ytdlp_pkg" ]; then
        echo "  安装 yt-dlp Python 包..."
        "$py_path" -m pip install --quiet --no-deps "$DOWNLOADS/ytdlp_pkg"/*.whl 2>/dev/null || \
        "$py_path" -m pip install --quiet yt-dlp 2>/dev/null || \
        echo "  警告: yt-dlp Python 包安装失败"
    fi

    # Create tarball
    echo "  打包..."
    local output="$PAYLOADS/$platform/runtime.tar.gz"
    tar -czf "$output" -C "$staging" .
    rm -rf "$staging"

    local size=$(du -sh "$output" | cut -f1)
    echo "  完成: $output ($size)"
}

echo "========================================="
echo "  组装平台负载"
echo "========================================="

# macOS arm64
build_payload "macos/arm64" "python3" \
    "$DOWNLOADS/macos/ffmpeg/ffmpeg.zip" \
    "$DOWNLOADS/ytdlp/yt-dlp_macos"

# macOS x86_64
build_payload "macos/x86_64" "python3" \
    "$DOWNLOADS/macos/ffmpeg/ffmpeg.zip" \
    "$DOWNLOADS/ytdlp/yt-dlp_macos"

# Windows
build_payload "windows" "python.exe" \
    "$DOWNLOADS/windows/ffmpeg.zip" \
    "$DOWNLOADS/ytdlp/yt-dlp.exe"

# Linux
build_payload "linux" "python3" \
    "$DOWNLOADS/linux/ffmpeg.tar.xz" \
    "$DOWNLOADS/ytdlp/yt-dlp_linux"

echo ""
echo "========================================="
echo "  组装完成!"
echo "========================================="
ls -lh "$PAYLOADS"/*/runtime.tar.gz
