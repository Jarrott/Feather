#!/bin/bash
set -euo pipefail

# 构建当前 Mac 架构的应用；签名身份必须显式固定，不安装、不启动、不修改系统权限。
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
SIGNING_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ] && [ -f "$PROJECT_ROOT/.signing-identity" ]; then
    SIGNING_IDENTITY="$(cat "$PROJECT_ROOT/.signing-identity")"
fi
if [ -z "$SIGNING_IDENTITY" ]; then
    printf '%s\n' 'Set CODE_SIGN_IDENTITY or save a certificate SHA-1 in .signing-identity.' >&2
    printf '%s\n' 'List available identities: security find-identity -v -p codesigning' >&2
    printf '%s\n' 'A stable Apple Development or Developer ID Application identity preserves app identity across builds.' >&2
    exit 1
fi
if [ "$SIGNING_IDENTITY" = '-' ]; then
    printf '%s\n' 'Warning: explicit ad-hoc signing changes app identity on rebuild; screen access may need approval again.' >&2
fi
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_ROOT/dist/Feather.app"
STAGING_DIR="$(mktemp -d "$PROJECT_ROOT/.build/Feather-package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/Feather.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$BIN_DIR/Feather" "$STAGED_APP/Contents/MacOS/Feather"
cp Resources/Info.plist "$STAGED_APP/Contents/Info.plist"
RESOURCE_BUNDLE="$BIN_DIR/Feather_Feather.bundle"
if [ ! -d "$RESOURCE_BUNDLE" ]; then
    printf 'Missing localization bundle: %s\n' "$RESOURCE_BUNDLE" >&2
    exit 1
fi
ditto "$RESOURCE_BUNDLE" "$STAGED_APP/Contents/Resources/Feather_Feather.bundle"
swift scripts/create-icon.swift "$PROJECT_ROOT/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_ROOT/.build/AppIcon.iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
# 正式发行启用 hardened runtime 和可信时间戳；本机开发保持原有签名要求。
SIGN_OPTIONS=(--force --sign "$SIGNING_IDENTITY" --identifier com.feather.screenshot)
if [ "${FEATHER_RELEASE:-0}" = '1' ]; then
    SIGN_OPTIONS+=(--options runtime --timestamp)
fi
codesign "${SIGN_OPTIONS[@]}" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
# 完整签名通过后才替换产物，避免覆盖正在运行的可执行文件；只保留一份本地回滚副本。
mkdir -p "$PROJECT_ROOT/dist"
PREVIOUS_APP="$PROJECT_ROOT/.build/Feather-previous.app"
if [ -d "$APP_DIR" ]; then
    rm -rf "$PREVIOUS_APP"
    mv "$APP_DIR" "$PREVIOUS_APP"
fi
if ! mv "$STAGED_APP" "$APP_DIR"; then
    if [ -d "$PREVIOUS_APP" ]; then mv "$PREVIOUS_APP" "$APP_DIR"; fi
    exit 1
fi
du -sh "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
printf '%s\n' 'Quit any running older copy before opening this build. A signing identity change requires fresh system approval.'
