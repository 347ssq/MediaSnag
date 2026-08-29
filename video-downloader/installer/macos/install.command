#!/bin/bash
set -e

# MediaSnag - macOS Installer
# Double-click to install. Supports arm64 and x86_64.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH="$(uname -m)"
INSTALL_DIR="$HOME/Library/ytdlp"

echo "========================================="
echo "  MediaSnag - Installer"
echo "========================================="
echo ""
echo "架构: $ARCH"
echo "安装目录: $INSTALL_DIR"
echo ""

# Step 1: Create install directory
echo "[1/5] 创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/userscript"

# Step 2: Detect platform payload
PAYLOAD_DIR=""
if [ -d "$SCRIPT_DIR/macos/arm64" ] && [ "$ARCH" = "arm64" ]; then
    PAYLOAD_DIR="$SCRIPT_DIR/macos/arm64"
elif [ -d "$SCRIPT_DIR/macos/x86_64" ] && [ "$ARCH" = "x86_64" ]; then
    PAYLOAD_DIR="$SCRIPT_DIR/macos/x86_64"
elif [ -d "$SCRIPT_DIR/macos/universal" ]; then
    PAYLOAD_DIR="$SCRIPT_DIR/macos/universal"
fi

if [ -n "$PAYLOAD_DIR" ]; then
    echo "[2/5] 解压运行环境..."
    tar -xzf "$PAYLOAD_DIR/runtime.tar.gz" -C "$INSTALL_DIR"
else
    echo "[2/5] 未找到预打包负载，尝试在线安装..."
    install_online
fi

# Step 3: Copy app source
echo "[3/5] 安装应用程序..."
APP_SOURCE="$SCRIPT_DIR/app"
if [ -d "$APP_SOURCE" ]; then
    cp -R "$APP_SOURCE/"* "$INSTALL_DIR/bin/"
fi
chmod +x "$INSTALL_DIR/bin/__main__.py" 2>/dev/null || true

# Create launcher script
cat > "$INSTALL_DIR/bin/launch.sh" << 'LAUNCHER'
#!/bin/bash
INSTALL_DIR="$HOME/Library/ytdlp"
PYTHON="$INSTALL_DIR/bin/python3"
APP="$INSTALL_DIR/bin"

if [ ! -x "$PYTHON" ]; then
    PYTHON="$(which python3)"
fi

if [ -n "$1" ]; then
    exec "$PYTHON" -m app "$@" &
else
    exec "$PYTHON" -m app &
fi
LAUNCHER
chmod +x "$INSTALL_DIR/bin/launch.sh"

# Step 4: Create .app bundle
echo "[4/5] 创建应用程序..."
bash "$SCRIPT_DIR/create_app.sh" "$INSTALL_DIR"

# Step 5: Register URL scheme
echo "[5/5] 注册 URL Scheme..."
APP_PATH="/Applications/MediaSnag.app"
if [ -d "$APP_PATH" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_PATH" 2>/dev/null || true
    echo "  URL Scheme 已注册: ytdl:// ytdla://"
fi

# Done
echo ""
echo "========================================="
echo "  安装完成!"
echo "========================================="
echo ""
echo "已安装:"
echo "  - MediaSnag.app → /Applications/"
echo "  - 运行环境 → $INSTALL_DIR/"
echo "  - URL Scheme: ytdl:// ytdla://"
echo ""

# Open browser to install Tampermonkey script
PORT=19527
for p in $(seq 19527 19537); do
    if ! lsof -i :$p >/dev/null 2>&1; then
        PORT=$p
        break
    fi
done

echo "正在启动服务器..."
"$INSTALL_DIR/bin/launch.sh" &
sleep 2

echo "请在浏览器中安装 Tampermonkey 脚本:"
echo "  http://127.0.0.1:$PORT/userscript.user.js"
echo ""
open "http://127.0.0.1:$PORT/userscript.user.js"

echo "按任意键退出安装程序..."
read -n 1
