#!/bin/bash

# OpenClaw Installer DMG 构建脚本
# 快速创建 DMG 安装包

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_NAME="OpenClawInstaller"
APP_NAME="OpenClawInstaller.app"
BUILD_DIR="$PROJECT_DIR/build"
DMG_NAME="OpenClawHelper.dmg"
GITHUB_REPO="firewolf189/GetClowhub"
DOCS_DIR="$PROJECT_DIR/docs"

echo "🚀 开始构建 OpenClaw Installer..."

# 清理旧的构建
if [ -d "$BUILD_DIR" ]; then
    echo "🧹 清理旧的构建文件..."
    rm -rf "$BUILD_DIR"
fi

# 构建项目
echo "🔨 构建项目..."
xcodebuild -project "$PROJECT_DIR/$PROJECT_NAME.xcodeproj" \
    -scheme "$PROJECT_NAME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    clean build

# 查找生成的 .app 文件
APP_PATH=$(find "$BUILD_DIR" -name "$APP_NAME" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ 错误: 找不到构建的 .app 文件"
    exit 1
fi

echo "✅ 应用构建成功: $APP_PATH"

# 将 Node.js 资源复制到 app bundle 中
echo "📦 添加 Node.js 资源到应用包..."
RESOURCES_SRC="$PROJECT_DIR/OpenClawInstaller/Resources"
RESOURCES_DEST="$APP_PATH/Contents/Resources"

if [ -d "$RESOURCES_SRC" ]; then
    # 复制资源文件到 app bundle
    cp -R "$RESOURCES_SRC/"* "$RESOURCES_DEST/"
    echo "✅ Node.js 资源已添加"

    # 显示已添加的文件
    echo "📋 已添加的资源:"
    ls -lh "$RESOURCES_DEST"/*.tar.gz 2>/dev/null || echo "   (无 .tar.gz 文件)"

    # 重新签名应用（包含新添加的资源）
    echo "🔐 重新签名应用..."
    codesign --force --deep --sign - "$APP_PATH" 2>&1 | grep -v "replacing existing signature" || true
    echo "✅ 签名完成"
else
    echo "⚠️  警告: Resources 目录不存在，跳过资源复制"
fi

# 创建 DMG
echo "📦 创建 DMG 安装包..."

# 卸载可能已挂载的 DMG
echo "🔄 卸载已挂载的 DMG..."
hdiutil detach "/Volumes/$PROJECT_NAME" 2>/dev/null || true
for vol in /Volumes/*OpenClaw*; do
    [ -d "$vol" ] && hdiutil detach "$vol" -force 2>/dev/null || true
done

# 删除旧的 DMG
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
rm -f "$DMG_PATH"
rm -f "$PROJECT_DIR/OpenClawInstaller.dmg"

# 使用用户私有临时目录（避免 /tmp 的权限和索引问题）
TMP_DMG_DIR=$(mktemp -d "${TMPDIR}openclaw_dmg.XXXXXX")

# 确保脚本退出时清理临时目录
cleanup() { rm -rf "$TMP_DMG_DIR"; }
trap cleanup EXIT

# 复制 .app 到临时目录
cp -R "$APP_PATH" "$TMP_DMG_DIR/"

# 移除隔离属性，避免"文件已损坏"错误
echo "🔓 移除隔离属性..."
xattr -cr "$TMP_DMG_DIR/OpenClawInstaller.app" 2>/dev/null || true

# 复制安装脚本（用户双击即可安装，自动处理 Gatekeeper）
INSTALL_SCRIPT="$PROJECT_DIR/Install OpenClaw Helper.command"
if [ -f "$INSTALL_SCRIPT" ]; then
    cp "$INSTALL_SCRIPT" "$TMP_DMG_DIR/"
    chmod +x "$TMP_DMG_DIR/Install OpenClaw Helper.command"
    xattr -cr "$TMP_DMG_DIR/Install OpenClaw Helper.command" 2>/dev/null || true
    echo "📄 已添加安装脚本"
fi

# 创建 Applications 文件夹的符号链接（拖拽安装备选方式）
ln -s /Applications "$TMP_DMG_DIR/Applications"

# 禁止 Spotlight 索引临时目录，避免 hdiutil 资源忙
touch "$TMP_DMG_DIR/.metadata_never_index"

# 等待 Spotlight 释放文件
sleep 1

# 生成 DMG（带重试）
echo "📦 正在打包 DMG..."
TMP_DMG="${TMP_DMG_DIR}.dmg"
rm -f "$TMP_DMG"

for i in 1 2 3; do
    if hdiutil create -volname "OpenClawHelper" \
        -srcfolder "$TMP_DMG_DIR" \
        -format UDZO \
        "$TMP_DMG" 2>/dev/null; then
        break
    fi
    echo "⏳ 资源忙，等待重试 ($i/3)..."
    sleep 3
done

if [ ! -f "$TMP_DMG" ]; then
    echo "❌ DMG 创建失败"
    exit 1
fi

# 移动到项目目录
mv "$TMP_DMG" "$DMG_PATH"

echo "✨ DMG 创建成功: $DMG_PATH"

# ===== Sparkle 自动更新: EdDSA 签名 + appcast.xml 生成 =====

# 从 Xcode 项目读取版本号
MARKETING_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/$PROJECT_NAME/Info.plist")
echo "📋 版本: $MARKETING_VERSION (Build $BUILD_NUMBER)"

# 查找 Sparkle 的 sign_update 工具
SIGN_UPDATE=""
# 优先查找 SPM 构建产物中的 sign_update
SPM_SIGN=$(find "$BUILD_DIR" -name "sign_update" -type f 2>/dev/null | head -1)
if [ -n "$SPM_SIGN" ] && [ -x "$SPM_SIGN" ]; then
    SIGN_UPDATE="$SPM_SIGN"
fi
# 也检查 Sparkle 安装路径
if [ -z "$SIGN_UPDATE" ] && [ -x "/usr/local/bin/sign_update" ]; then
    SIGN_UPDATE="/usr/local/bin/sign_update"
fi

if [ -n "$SIGN_UPDATE" ]; then
    echo "🔏 对 DMG 进行 EdDSA 签名..."
    EDDSA_SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1 | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')

    if [ -z "$EDDSA_SIGNATURE" ]; then
        # sign_update 有时直接输出签名字符串
        EDDSA_SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH" 2>&1 | tail -1)
    fi
    echo "✅ EdDSA 签名完成"
else
    echo "⚠️  未找到 sign_update 工具，跳过 EdDSA 签名"
    echo "   请运行: swift run sign_update --help （在 Sparkle 源码目录中）"
    EDDSA_SIGNATURE="SIGNATURE_PLACEHOLDER"
fi

# 获取 DMG 文件大小
DMG_SIZE=$(stat -f%z "$DMG_PATH")
DMG_DOWNLOAD_URL="https://github.com/$GITHUB_REPO/releases/download/v$MARKETING_VERSION/$DMG_NAME"

# 生成 appcast.xml
echo "📝 生成 appcast.xml..."
mkdir -p "$DOCS_DIR"

cat > "$DOCS_DIR/appcast.xml" << APPCAST_EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>OpenClaw Helper Updates</title>
    <link>https://firewolf189.github.io/GetClowhub/appcast.xml</link>
    <description>OpenClaw Helper 版本更新</description>
    <language>zh-cn</language>
    <item>
      <title>Version $MARKETING_VERSION</title>
      <sparkle:version>$BUILD_NUMBER</sparkle:version>
      <sparkle:shortVersionString>$MARKETING_VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>OpenClaw Helper $MARKETING_VERSION</h2>
        <ul>
          <li>版本更新</li>
        </ul>
      ]]></description>
      <pubDate>$(date -R)</pubDate>
      <enclosure url="$DMG_DOWNLOAD_URL"
                 length="$DMG_SIZE"
                 type="application/octet-stream"
                 sparkle:edSignature="$EDDSA_SIGNATURE" />
    </item>
  </channel>
</rss>
APPCAST_EOF

echo "✅ appcast.xml 已生成: $DOCS_DIR/appcast.xml"
echo ""
echo "===== 发版步骤 ====="
echo "1. gh release create v$MARKETING_VERSION \"$DMG_PATH\" --title \"v$MARKETING_VERSION\" --notes \"版本更新\""
echo "2. git add docs/appcast.xml && git commit -m \"update appcast v$MARKETING_VERSION\" && git push"
echo "===================="

echo "🎉 构建完成！"
