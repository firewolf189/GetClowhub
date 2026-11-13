#!/usr/bin/env bash

set -Eeuo pipefail

# Upload a notarized DMG to Alibaba Cloud OSS.
# Usage:
#   ./upload_oss_release.sh [version] [dmg_path]
#
# Example:
#   ./upload_oss_release.sh v1.1.93 \
#     "/path/to/HoldClaw-v1.1.93-build102-notarized.dmg"

VERSION="${1:-v1.1.93}"
DMG_PATH="${2:-}"
BUCKET="${OSS_BUCKET:-fp-getclawhub}"
ENDPOINT="${OSS_ENDPOINT:-https://oss-cn-hangzhou.aliyuncs.com}"
PARALLEL="${OSS_PARALLEL:-4}"
PART_SIZE="${OSS_PART_SIZE:-32M}"
CHECKPOINT_DIR="${OSS_CHECKPOINT_DIR:-/tmp/holdclaw-oss-${VERSION}}"

if [[ "$VERSION" != v* ]]; then
    VERSION="v${VERSION}"
fi

if [[ -z "$DMG_PATH" ]]; then
    DMG_PATH="$(cd "$(dirname "$0")/.." && pwd)/审查附件/正式发版准备-${VERSION}/HoldClaw-${VERSION}-build102-notarized.dmg"
fi

if ! command -v ossutil >/dev/null 2>&1; then
    echo "Error: ossutil was not found in PATH." >&2
    exit 1
fi

if [[ ! -f "$DMG_PATH" ]]; then
    echo "Error: DMG file does not exist:" >&2
    echo "  $DMG_PATH" >&2
    exit 1
fi

if ! [[ "$PARALLEL" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: OSS_PARALLEL must be a positive integer." >&2
    exit 1
fi

VERSION_OBJECT="oss://${BUCKET}/${VERSION}/GetClawHub.dmg"
LATEST_OBJECT="oss://${BUCKET}/latest/GetClawHub.dmg"
FILE_SIZE="$(stat -f '%z' "$DMG_PATH")"
FILE_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

echo "DMG:        $DMG_PATH"
echo "Size:       $FILE_SIZE bytes"
echo "SHA-256:    $FILE_SHA256"
echo "Endpoint:   $ENDPOINT"
echo "Version:    $VERSION_OBJECT"
echo "Latest:     $LATEST_OBJECT"
echo "Parallel:   $PARALLEL"
echo "Part size:  $PART_SIZE"
echo "Checkpoint: $CHECKPOINT_DIR"
echo

mkdir -p "$CHECKPOINT_DIR"

upload() {
    local destination="$1"
    echo "Uploading to $destination"
    echo "Progress is shown by ossutil below. Do not close this terminal."
    ossutil cp -f \
        --endpoint "$ENDPOINT" \
        --acl public-read \
        --parallel "$PARALLEL" \
        --part-size "$PART_SIZE" \
        --connect-timeout 15 \
        --read-timeout 60 \
        --retry-times 5 \
        --checkpoint-dir "$CHECKPOINT_DIR" \
        "$DMG_PATH" \
        "$destination"
    echo
}

verify() {
    local object="$1"
    echo "Verifying $object"
    ossutil stat "$object"
    echo
}

upload "$VERSION_OBJECT"
verify "$VERSION_OBJECT"

upload "$LATEST_OBJECT"
verify "$LATEST_OBJECT"

echo "OSS upload completed."
echo "Version URL: https://${BUCKET}.oss-cn-hangzhou.aliyuncs.com/${VERSION}/GetClawHub.dmg"
echo "Latest URL:  https://${BUCKET}.oss-cn-hangzhou.aliyuncs.com/latest/GetClawHub.dmg"
