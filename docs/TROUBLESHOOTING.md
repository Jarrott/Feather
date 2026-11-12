# 权限与启动排障

## 首次使用

首次截图需在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制 / 屏幕录制」中允许 Feather。应用只读取静态屏幕图像，不录音、不录视频。授权后再次截图；系统要求时退出并重新打开应用。

建议先将应用放入「应用程序」文件夹，再授权。更新时从菜单栏退出旧版，再打开新版，避免多个副本争用快捷键。

## 已授权却反复提示

1. 从菜单栏退出旧版，打开要使用的 Feather。错误提示中的「在 Finder 中显示当前应用」可定位实际运行的副本。
2. 在系统屏幕录制权限列表中，移除失效的旧 Feather 条目，再用加号添加当前应用并授权。
3. 完全退出并重新打开这份应用，再截图。

从 ad-hoc 签名切换到开发证书时，系统可能要求重新授权。后续保持同一签名身份和安装位置。

如果重新添加后仍反复提示，可检查系统是否保留了旧签名的授权记录：

```bash
/usr/bin/log show --last 10m --info --debug --predicate 'process == "tccd" AND eventMessage CONTAINS "Failed to match existing code requirement for subject com.feather.screenshot"'
```

若日志确认旧 `cdhash` 与当前证书要求不匹配，先退出 Feather，再仅重置本应用的授权：

```bash
tccutil reset ScreenCapture com.feather.screenshot
```

**此操作会撤销 Feather 的截图授权，不影响其他应用。** 重新打开当前应用并触发截图，在系统界面重新授权，按提示退出重开。不要重置整个系统权限库或绕过 TCC。

参考：[Apple 关于 ad-hoc 重建与权限丢失的说明](https://developer.apple.com/forums/thread/819406)。

## 构建与签名

- 构建脚本从 `CODE_SIGN_IDENTITY` 环境变量或本机 `.signing-identity` 文件读取证书，未配置时会停止。
- Apple Development 用于本机开发；对外分发需要 Developer ID Application 签名和 Apple 公证。脚本默认按当前 Mac 的 CPU 架构构建；`FEATHER_RELEASE=1` 或 `FEATHER_UNIVERSAL=1` 时构建 arm64 + x86_64 通用二进制。
- 仅做临时构建验证时可使用 `CODE_SIGN_IDENTITY=- ./scripts/build-app.sh`。ad-hoc 重建可能改变应用身份，不能保证已有权限延续。
- 在 Xcode 中打开 `Package.swift` 开发；验证截图权限与菜单栏时，运行打包后的 `.app`。
