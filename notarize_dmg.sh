#!/bin/bash

# GetClawHub DMG 公证脚本
# 对已签名的 DMG 提交 Apple 公证
#
# 用法:
#   bash notarize_dmg.sh                    # 公证当前目录的 GetClawHub.dmg
#   bash notarize_dmg.sh /path/to/file.dmg  # 公证指定的 DMG
#
# 凭据配置 (二选一):
#   方式1: 环境变量
#     APPLE_ID=xxx APPLE_APP_PASSWORD=xxx bash notarize_dmg.sh
#
#   方式2: Keychain Profile (推荐)
#     先存储: xcrun notarytool store-credentials "notary-profile" \
#               --apple-id xxx --team-id LJQJ5BHW7G --password xxx
#     再使用: bash notarize_dmg.sh

set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEAM_ID="LJQJ5BHW7G"

# DMG 路径: 参数指定 或 默认
DMG_PATH="${1:-$PROJECT_DIR/GetClawHub.dmg}"

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ 找不到 DMG 文件: $DMG_PATH"
    echo "用法: bash notarize_dmg.sh [DMG路径]"
    exit 1
fi

echo "📋 DMG 文件: $DMG_PATH ($(du -h "$DMG_PATH" | awk '{print $1}'))"

# ===== 验证签名 =====
echo "🔍 验证 DMG 内 app 签名..."

# 挂载 DMG
MOUNT_OUTPUT=$(hdiutil attach "$DMG_PATH" -nobrowse 2>&1)
MOUNT_POINT=$(echo "$MOUNT_OUTPUT" | grep "/Volumes/" | awk -F'\t' '{print $NF}')

if [ -z "$MOUNT_POINT" ]; then
    echo "❌ 无法挂载 DMG"
    exit 1
fi

cleanup_mount() {
    hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
}
trap cleanup_mount EXIT

APP_IN_DMG="$MOUNT_POINT/GetClawHub.app"
if [ ! -d "$APP_IN_DMG" ]; then
    echo "❌ DMG 中找不到 GetClawHub.app"
    exit 1
fi

if codesign --verify --deep --strict "$APP_IN_DMG" 2>&1; then
    echo "✅ 签名验证通过"
else
    echo "❌ 签名验证失败，请先用 build_dmg.sh 构建签名"
    exit 1
fi

# 显示签名信息
codesign -dvvv "$APP_IN_DMG" 2>&1 | grep -E "(Authority|Timestamp|runtime)" | head -5
echo ""

# 卸载 DMG
hdiutil detach "$MOUNT_POINT" -force 2>/dev/null || true
trap - EXIT

# ===== 确定凭据方式 =====
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_PASSWORD="${APPLE_APP_PASSWORD:-}"

USE_KEYCHAIN=false
if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_PASSWORD" ]; then
    # 尝试使用 keychain profile
    if xcrun notarytool history --keychain-profile "notary-profile" >/dev/null 2>&1; then
        USE_KEYCHAIN=true
        echo "🔑 使用 Keychain Profile: notary-profile"
    else
        echo "❌ 未提供凭据"
        echo ""
        echo "方式1: APPLE_ID=xxx APPLE_APP_PASSWORD=xxx bash notarize_dmg.sh"
        echo "方式2: 先运行 xcrun notarytool store-credentials \"notary-profile\" --apple-id xxx --team-id $TEAM_ID --password xxx"
        exit 1
    fi
else
    echo "🔑 使用 Apple ID: $APPLE_ID"
fi

# ===== 构建 notarytool 参数 =====
if [ "$USE_KEYCHAIN" = true ]; then
    AUTH_ARGS=(--keychain-profile "notary-profile")
else
    AUTH_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$TEAM_ID")
fi

# ===== 提交公证 =====
echo "📤 提交 Apple 公证..."

SUBMIT_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" \
    "${AUTH_ARGS[@]}" \
    --s3-acceleration 2>&1)

echo "$SUBMIT_OUTPUT"

# 提取 Submission ID
SUBMISSION_ID=$(echo "$SUBMIT_OUTPUT" | grep "id:" | head -1 | awk '{print $2}')

if [ -z "$SUBMISSION_ID" ]; then
    echo "❌ 无法获取 Submission ID"
    exit 1
fi

# 检查是否上传成功
if ! echo "$SUBMIT_OUTPUT" | grep -q "Successfully uploaded"; then
    echo "⚠️  未检测到上传成功确认，可能上传不完整"
fi

echo ""
echo "⏳ 等待公证结果 (ID: $SUBMISSION_ID)..."
echo "   每 30 秒检查一次，超时 15 分钟自动退出"

# ===== 轮询公证状态 =====
MAX_POLLS=30
POLL_COUNT=0

while [ $POLL_COUNT -lt $MAX_POLLS ]; do
    sleep 30
    POLL_COUNT=$((POLL_COUNT + 1))

    STATUS_OUTPUT=$(xcrun notarytool info "$SUBMISSION_ID" \
        "${AUTH_ARGS[@]}" 2>&1) || true

    STATUS=$(echo "$STATUS_OUTPUT" | grep "status:" | head -1 | sed 's/.*status: //')

    if [ "$STATUS" = "Accepted" ]; then
        echo "✅ 公证通过!"
        echo ""

        echo "📎 Staple 公证票据到 DMG..."
        xcrun stapler staple "$DMG_PATH"
        echo "✅ 公证完成！DMG 已可分发: $DMG_PATH"
        exit 0

    elif [ "$STATUS" = "Invalid" ] || [ "$STATUS" = "Rejected" ]; then
        echo "❌ 公证失败: $STATUS"
        echo ""
        echo "📋 详细日志:"
        xcrun notarytool log "$SUBMISSION_ID" \
            "${AUTH_ARGS[@]}" 2>&1 || true
        exit 1

    else
        echo "   [$POLL_COUNT/$MAX_POLLS] 状态: ${STATUS:-未知}..."
    fi
done

echo ""
echo "⚠️  超时：公证仍在处理中 (ID: $SUBMISSION_ID)"
echo "   稍后手动检查: xcrun notarytool info $SUBMISSION_ID ${AUTH_ARGS[*]}"
echo "   公证通过后手动 staple: xcrun stapler staple \"$DMG_PATH\""
exit 2
