#!/bin/bash
set -e

# MediaSnag - Linux Installer
# Usage: bash install.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/ytdlp"
BIN_DIR="$HOME/.local/bin"

echo "========================================="
echo "  MediaSnag - Linux 安装程序"
echo "========================================="
echo ""
echo "安装目录: $INSTALL_DIR"
echo ""

# Step 1: Create directories
echo "[1/5] 创建安装目录..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/userscript"
mkdir -p "$BIN_DIR"

# Step 2: Extract payload
echo "[2/5] 解压运行环境..."
if [ -f "$SCRIPT_DIR/linux/runtime.tar.gz" ]; then
    tar -xzf "$SCRIPT_DIR/linux/runtime.tar.gz" -C "$INSTALL_DIR"
else
    echo "  未找到预打包负载，将使用系统 Python..."
fi

# Step 3: Copy app source
echo "[3/5] 安装应用程序..."
if [ -d "$SCRIPT_DIR/app" ]; then
    cp -R "$SCRIPT_DIR/app/"* "$INSTALL_DIR/bin/"
fi

# Step 4: Create launcher script
echo "[4/5] 创建启动器..."
cat > "$BIN_DIR/mediasnag" << LAUNCHER
#!/bin/bash
INSTALL_DIR="$INSTALL_DIR"
PYTHON="\$INSTALL_DIR/bin/python3"

if [ ! -x "\$PYTHON" ]; then
    PYTHON="\$(which python3 2>/dev/null)"
fi

if [ -z "\$PYTHON" ]; then
    echo "错误: 未找到 Python 3"
    exit 1
fi

export PYTHONPATH="\$INSTALL_DIR/bin:\$PYTHONPATH"

if [ -n "\$1" ]; then
    exec "\$PYTHON" -c "
import sys
sys.path.insert(0, '\$INSTALL_DIR/bin')
from app.__main__ import main
sys.argv = ['mediasnag', '\$1']
main()
"
else
    exec "\$PYTHON" -c "
import sys
sys.path.insert(0, '\$INSTALL_DIR/bin')
from app.__main__ import main
sys.argv = ['mediasnag']
main()
"
fi
LAUNCHER
chmod +x "$BIN_DIR/mediasnag"

# Step 5: Register URL scheme via .desktop file
echo "[5/5] 注册 URL Scheme..."
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"

cat > "$DESKTOP_DIR/mediasnag.desktop" << DESKTOP
[Desktop Entry]
Type=Application
Name=MediaSnag
Comment=MediaSnag
Exec=$BIN_DIR/mediasnag %u
Terminal=false
NoDisplay=true
MimeType=x-scheme-handler/ytdl;x-scheme-handler/ytdla;
Categories=Network;
DESKTOP

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

echo ""
echo "========================================="
echo "  安装完成!"
echo "========================================="
echo ""
echo "已安装:"
echo "  - 运行环境 → $INSTALL_DIR/"
echo "  - 启动命令 → $BIN_DIR/mediasnag"
echo "  - URL Scheme: ytdl:// ytdla://"
echo ""
echo "提示: 确保 $BIN_DIR 在 PATH 中"
echo "  如不在，请添加: export PATH=\"$BIN_DIR:\$PATH\""
echo ""

# Start server and open userscript
echo "正在启动服务器..."
"$BIN_DIR/mediasnag" --serve &
SERVER_PID=$!
sleep 2

PORT=19527
echo "请在浏览器中安装 Tampermonkey 脚本:"
echo "  http://127.0.0.1:$PORT/userscript.user.js"
echo ""

if command -v xdg-open &>/dev/null; then
    xdg-open "http://127.0.0.1:$PORT/userscript.user.js"
fi

echo "按 Ctrl+C 退出安装程序..."
wait $SERVER_PID
