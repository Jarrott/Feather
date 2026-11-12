#!/bin/bash
set -euo pipefail

# 本机验证入口：依次检查格式、语法、回归、6K 基准及签名构建，任一步失败立即停止。
# 沿用 build-app.sh 的固定签名配置；不安装、启动应用、触发截图或自动提交代码。
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"
swift --version
swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
bash -n scripts/build-app.sh scripts/package-release.sh scripts/validate.sh
plutil -lint Resources/Info.plist
swift test
FEATHER_RUN_BENCHMARKS=1 swift test -c release --filter RenderingPerformanceTests
./scripts/build-app.sh
codesign --verify --strict dist/Feather.app
git diff --check
