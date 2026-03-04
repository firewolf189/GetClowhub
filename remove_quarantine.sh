#!/bin/bash

# 移除 OpenClawInstaller 的隔离属性脚本

echo "==========================================="
echo "OpenClawInstaller 修复工具"
echo "==========================================="
echo ""
echo "此脚本将移除应用的隔离标记，允许在 macOS 上运行"
echo ""

# 查找应用位置
APP_LOCATIONS=(
    "/Applications/OpenClawInstaller.app"
    "$HOME/Applications/OpenClawInstaller.app"
    "$(dirname "$0")/OpenClawInstaller.app"
)

APP_PATH=""
for location in "${APP_LOCATIONS[@]}"; do
    if [ -d "$location" ]; then
        APP_PATH="$location"
        break
    fi
done

if [ -z "$APP_PATH" ]; then
    echo "❌ 错误: 找不到 OpenClawInstaller.app"
    echo ""
    echo "请将此脚本放在与 OpenClawInstaller.app 相同的目录，或者"
    echo "将应用安装到 /Applications 目录"
    exit 1
fi

echo "✅ 找到应用: $APP_PATH"
echo ""
echo "正在移除隔离属性..."

# 移除隔离属性
xattr -dr com.apple.quarantine "$APP_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✨ 修复完成！"
    echo ""
    echo "现在您可以正常打开 OpenClawInstaller 了"
    echo ""
    echo "提示: 首次打开时，系统可能会显示安全提示"
    echo "      点击 '打开' 即可"
else
    echo ""
    echo "❌ 修复失败"
    echo ""
    echo "请尝试手动执行："
    echo "sudo xattr -dr com.apple.quarantine \"$APP_PATH\""
fi
