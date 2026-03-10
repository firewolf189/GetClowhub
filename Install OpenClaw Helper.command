#!/bin/bash
# GetClawHub 安装脚本
# 双击此文件即可自动安装（自动处理 Gatekeeper 信任问题）

clear
echo "================================================"
echo "        GetClawHub Installer"
echo "================================================"
echo ""

# 获取脚本所在目录（即 DMG 挂载目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GetClawHub.app"
APP_SRC="$SCRIPT_DIR/$APP_NAME"
APP_DEST="/Applications/$APP_NAME"

# 检查 app 是否存在
if [ ! -d "$APP_SRC" ]; then
    echo "Error: $APP_NAME not found"
    echo "Please run this script from the DMG."
    echo ""
    echo "Press Enter to exit..."
    read
    exit 1
fi

echo "Installing GetClawHub..."
echo ""

# 如果目标已存在，先关闭正在运行的实例
if pgrep -x "GetClawHub" > /dev/null 2>&1; then
    echo "   -> Closing running GetClawHub..."
    killall "GetClawHub" 2>/dev/null
    sleep 1
fi

# 如果目标已存在，先删除
if [ -d "$APP_DEST" ]; then
    echo "   -> Removing old version..."
    rm -rf "$APP_DEST" 2>/dev/null
    if [ -d "$APP_DEST" ]; then
        echo "   -> Requires admin permission..."
        sudo rm -rf "$APP_DEST"
    fi
fi

# 复制到 Applications
echo "   -> Copying to Applications..."
cp -R "$APP_SRC" "$APP_DEST" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "   -> Requires admin permission..."
    sudo cp -R "$APP_SRC" "$APP_DEST"
fi

# 移除 quarantine 属性（解决 Gatekeeper 信任问题）
echo "   -> Removing quarantine attribute..."
xattr -cr "$APP_DEST" 2>/dev/null
if [ $? -ne 0 ]; then
    sudo xattr -cr "$APP_DEST" 2>/dev/null
fi

# 验证安装
if [ -d "$APP_DEST" ]; then
    echo ""
    echo "Done! GetClawHub has been installed."
    echo ""
    echo "   Launching GetClawHub..."
    open "$APP_DEST"
else
    echo ""
    echo "Installation failed. Please drag $APP_NAME to Applications manually."
fi

echo ""
echo "Press Enter to close..."
read
