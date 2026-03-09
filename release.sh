#!/bin/bash

# OpenClaw Helper 一键发版脚本
# 用法: ./release.sh <版本号>
# 示例: ./release.sh 1.0.3

set -e

# ===== 参数检查 =====
if [ -z "$1" ]; then
    echo "用法: ./release.sh <版本号>"
    echo "示例: ./release.sh 1.0.3"
    exit 1
fi

NEW_VERSION="$1"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$PROJECT_DIR/OpenClawInstaller/Info.plist"
PBXPROJ="$PROJECT_DIR/OpenClawInstaller.xcodeproj/project.pbxproj"

# 读取当前版本
OLD_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")
OLD_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
NEW_BUILD=$((OLD_BUILD + 1))

echo "====================================="
echo "  OpenClaw Helper 发版"
echo "  $OLD_VERSION (Build $OLD_BUILD) → $NEW_VERSION (Build $NEW_BUILD)"
echo "====================================="
echo ""

# ===== 确认 =====
read -p "确认发版? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "已取消"
    exit 0
fi

# ===== 1. 更新版本号 =====
echo ""
echo "📋 [1/5] 更新版本号..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $NEW_VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEW_BUILD" "$PLIST"
sed -i '' "s/MARKETING_VERSION = $OLD_VERSION;/MARKETING_VERSION = $NEW_VERSION;/g" "$PBXPROJ"
sed -i '' "s/CURRENT_PROJECT_VERSION = $OLD_BUILD;/CURRENT_PROJECT_VERSION = $NEW_BUILD;/g" "$PBXPROJ"
echo "✅ 版本号已更新: $NEW_VERSION (Build $NEW_BUILD)"

# ===== 2. 构建 DMG =====
echo ""
echo "📦 [2/5] 构建 DMG..."
bash "$PROJECT_DIR/build_dmg.sh"

DMG_PATH="$PROJECT_DIR/OpenClawHelper.dmg"
if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG 构建失败"
    exit 1
fi

# ===== 3. 输入更新说明 =====
echo ""
echo "📝 [3/5] 请输入更新说明 (直接回车使用默认):"
read -r RELEASE_NOTES
if [ -z "$RELEASE_NOTES" ]; then
    RELEASE_NOTES="版本 $NEW_VERSION 更新"
fi

# ===== 4. 创建 GitHub Release =====
echo ""
echo "🚀 [4/5] 创建 GitHub Release..."
gh release create "v$NEW_VERSION" "$DMG_PATH" \
    --title "v$NEW_VERSION" \
    --notes "$RELEASE_NOTES"
echo "✅ Release 已创建"

# ===== 5. 提交并推送 =====
echo ""
echo "📤 [5/5] 提交并推送..."
cd "$PROJECT_DIR"
git add docs/appcast.xml \
    OpenClawInstaller/Info.plist \
    OpenClawInstaller.xcodeproj/project.pbxproj
git add -A  # 捕获其他可能的改动
git commit -m "release v$NEW_VERSION: $RELEASE_NOTES"
git push

echo ""
echo "====================================="
echo "  🎉 v$NEW_VERSION 发版完成!"
echo ""
echo "  Release: https://github.com/firewolf189/GetClowhub/releases/tag/v$NEW_VERSION"
echo "  appcast: https://firewolf189.github.io/GetClowhub/appcast.xml"
echo "====================================="
