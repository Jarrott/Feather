#!/bin/bash
set -euo pipefail

# 仅打包已通过 Developer ID 签名和公证的当前构建，不创建 Git 标签或发布 Release。
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
APP="dist/Feather.app"
: "${NOTARY_PROFILE:?Set a notarytool keychain profile before packaging a release.}"
codesign --verify --strict "$APP"
SIGNATURE="$(codesign -dv --verbose=4 "$APP" 2>&1)"
if ! [[ "$SIGNATURE" == *'Authority=Developer ID Application:'* ]]; then
    printf '%s\n' 'Public releases require a Developer ID Application signature.' >&2
    exit 1
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
# 包含 arm64 与 x86_64 时标记为 universal，否则使用实际二进制架构（而非构建机架构）。
ARCHS="$(lipo -archs "$APP/Contents/MacOS/Feather")"
if [[ " $ARCHS " == *' arm64 '* && " $ARCHS " == *' x86_64 '* ]]; then
    ARCHITECTURE=universal
else
    ARCHITECTURE="${ARCHS// /-}"
fi
ARCHIVE="dist/Feather-${VERSION}-${ARCHITECTURE}.zip"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute "$APP"
ditto -c -k --keepParent "$APP" "$ARCHIVE"
shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256"
printf 'Release archive: %s\n' "$ARCHIVE"
