#!/bin/bash

# 脚本用于将 Resources 目录添加到 Xcode 项目中

PROJECT_DIR="/Users/chencheng/Desktop/openclaw安装配置macos/OpenClawInstaller"
cd "$PROJECT_DIR"

echo "=========================================="
echo "添加 Node.js 资源到 Xcode 项目"
echo "=========================================="
echo ""

# 检查资源文件是否存在
if [ ! -f "OpenClawInstaller/Resources/node-v24.14.0-darwin-arm64.tar.gz" ]; then
    echo "❌ 错误: 资源文件不存在"
    exit 1
fi

echo "✅ 找到资源文件"
echo ""

# 使用 PlistBuddy 或直接用 plutil 不太合适，因为 pbxproj 不是 plist 格式
# 最简单的方法是手动指导用户在 Xcode 中添加

echo "📝 请按照以下步骤手动添加资源："
echo ""
echo "1. 在 Xcode 中打开项目"
echo "   open OpenClawInstaller.xcodeproj"
echo ""
echo "2. 在左侧项目导航器中，右键点击 OpenClawInstaller 文件夹"
echo ""
echo "3. 选择 'Add Files to OpenClawInstaller...'"
echo ""
echo "4. 选择 OpenClawInstaller/Resources 文件夹"
echo ""
echo "5. 确保勾选："
echo "   ✓ Copy items if needed"
echo "   ✓ Create folder references (选择蓝色文件夹)"
echo "   ✓ Add to targets: OpenClawInstaller"
echo ""
echo "6. 点击 'Add'"
echo ""
echo "=========================================="
echo ""
echo "或者，让我尝试自动打开 Xcode 并显示资源文件..."
echo ""

# 打开 Xcode 项目
open OpenClawInstaller.xcodeproj

# 在 Finder 中显示资源文件夹
open OpenClawInstaller/Resources/

echo "✅ 已打开 Xcode 和资源文件夹"
echo ""
echo "请将 Resources 文件夹拖拽到 Xcode 的项目导航器中"
