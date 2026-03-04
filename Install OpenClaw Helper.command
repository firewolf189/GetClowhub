#!/bin/bash
# OpenClaw Helper 安装脚本
# 双击此文件即可自动安装

clear
echo "================================================"
echo "        OpenClaw Helper 安装程序"
echo "================================================"
echo ""

# 获取脚本所在目录（即 DMG 挂载目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="OpenClawInstaller.app"
APP_SRC="$SCRIPT_DIR/$APP_NAME"
APP_DEST="/Applications/$APP_NAME"

# 检查 app 是否存在
if [ ! -d "$APP_SRC" ]; then
    echo "❌ 错误: 找不到 $APP_NAME"
    echo "   请确保从 DMG 中运行此脚本"
    echo ""
    echo "按回车键退出..."
    read
    exit 1
fi

echo "📦 正在安装 OpenClaw Helper..."
echo ""

# 移除 quarantine 属性
echo "   → 移除安全隔离属性..."
xattr -cr "$APP_SRC" 2>/dev/null

# 如果目标已存在，先删除
if [ -d "$APP_DEST" ]; then
    echo "   → 移除旧版本..."
    rm -rf "$APP_DEST" 2>/dev/null
    if [ -d "$APP_DEST" ]; then
        echo "   → 需要管理员权限移除旧版本..."
        sudo rm -rf "$APP_DEST"
    fi
fi

# 复制到 Applications
echo "   → 复制到 Applications 文件夹..."
cp -R "$APP_SRC" "$APP_DEST" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "   → 需要管理员权限..."
    sudo cp -R "$APP_SRC" "$APP_DEST"
fi

# 移除目标的 quarantine
xattr -cr "$APP_DEST" 2>/dev/null

# 验证安装
if [ -d "$APP_DEST" ]; then
    echo ""
    echo "✅ 安装成功！"
    echo ""
    echo "   正在启动 OpenClaw Helper..."
    open "$APP_DEST"
    echo ""
    echo "   如果没有自动启动，请在 Applications 中找到 OpenClaw Helper 打开"
else
    echo ""
    echo "❌ 安装失败，请手动将 $APP_NAME 拖入 Applications 文件夹"
fi

echo ""
echo "按回车键关闭此窗口..."
read
