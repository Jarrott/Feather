# 轻截 Feather

一款原生、轻量、离线的 macOS 截图工具。参考 [PixPin](https://pixpin.com/zh-hans/) 的框选、就地标注、快速输出流程，独立实现和设计。平时只驻留菜单栏，没有工作台或独立编辑窗口。

## 运行

需要 **macOS 14+**。开发需要 Xcode 16+ / Swift 6 工具链，无第三方依赖。

先选择固定的 Apple Development（本机开发）或 Developer ID Application（分发）签名证书：

```bash
security find-identity -v -p codesigning
# 将选定证书的 SHA-1 写入本机配置；不要提交此文件。
printf '%s\n' 'CERTIFICATE_SHA1' > .signing-identity
./scripts/build-app.sh
open dist/Feather.app
```

也可通过 `CODE_SIGN_IDENTITY` 环境变量指定证书。脚本没有配置时会停止，不会静默回退 ad-hoc。仅做临时构建验证时可显式设置 `CODE_SIGN_IDENTITY=-`，但此模式不保证重建后的权限延续。

可将 `dist/Feather.app` 拖到「应用程序」文件夹后再授权使用，避免移动应用后权限记录变化。构建使用当前 Mac 的 CPU 架构和选定的固定证书；Apple Development 用于本机开发，对外分发需要 Developer ID 签名和 Apple 公证。更新时先从菜单栏退出旧版本，再打开新版，避免两个进程争用同一快捷键。

首次截图由 ScreenCaptureKit 发起系统授权，请允许「屏幕与系统音频录制 / 屏幕录制」。本应用只读取静态屏幕图像，不录音、不录视频。完成授权后再次截图；系统要求时退出并重新打开应用。

## 已授权却反复提示

1. 从菜单栏退出正在运行的旧版，打开新构建的 `dist/Feather.app`。
2. 在「系统设置 → 隐私与安全性 → 屏幕与系统音频录制」中，若旧 Feather 条目已打开但仍失败，移除旧条目，再用加号添加当前 `dist/Feather.app` 并授权。
3. 完全退出并重新打开这份应用，再截图。错误提示里的「在 Finder 中显示当前应用」可定位实际运行的副本。

从旧版 ad-hoc 切换为开发证书时，系统可能要求重新授权一次；之后保持同一签名身份和安装位置。1.1.1 不再以 `CGPreflightScreenCaptureAccess()` 的 false 结果直接拦截截图，而由 ScreenCaptureKit 实际验证；只把 `SCStreamError.userDeclined` 作为授权拒绝，不将普通截图错误混报成权限问题。

如果重新添加后仍反复提示，系统可能保留了旧 ad-hoc 签名的授权记录。可先检查针对本应用的日志：

```bash
/usr/bin/log show --last 10m --info --debug --predicate 'process == "tccd" AND eventMessage CONTAINS "Failed to match existing code requirement for subject com.feather.screenshot"'
```

若输出包含旧 `cdhash` 与当前证书要求不匹配，先退出轻截，再仅重置本应用的屏幕录制授权：

```bash
tccutil reset ScreenCapture com.feather.screenshot
open dist/Feather.app
```

此操作会撤销 Feather 原来的截图授权，需要重新触发截图，在系统界面授权并按提示退出重开；不影响其他应用。由助手代执行时，应先取得用户对这项权限重置的明确同意。

不要通过重置整个系统权限库或绕过 TCC 来处理此问题。[Apple 开发者技术支持说明了 ad-hoc 重建与权限丢失的关系](https://developer.apple.com/forums/thread/819406)。

## 使用

1. **左键菜单栏图标**，或按 **⇧⌘2**，开始区域截图。
2. 拖动框选后，在原位置显示绿色选区、八个调整点和一排悬浮按钮。拖动选区移动，拖动边角改变范围。
3. 点击矩形、椭圆、箭头、画笔、高亮、文字或遮盖，就地标注；选中工具时展开颜色和粗细选项。
4. 点击保存或 `⌘S`，保存 PNG 并收起；点击 **✓**、`⌘C` 或 `Enter`，复制并收起。
5. **右键菜单栏图标 → 偏好设置**，更改快捷键、保存目录、保存后复制和鼠标显示选项。

默认保存到 `~/Pictures/Feather`，保存后默认同时复制。工具条的保存按钮右键菜单提供「另存为」。`Esc`、右键选区或 **×** 会直接放弃当前截图；未保存的内容不保留。保存失败会保留选区和全部标注。

| 快捷键 | 行为 |
| --- | --- |
| ⇧⌘2（可自定义） | 全局区域截图；会话中再次触发则聚焦当前选区 |
| V / 0 | 切回移动选区模式 |
| 1–7 | 矩形、椭圆、箭头、画笔、高亮、文字、遮盖 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做标注 |
| ⌘S / ⇧⌘S | 快速保存 / 另存为，成功后收起 |
| ⌘C / Enter | 复制并收起 |
| Esc | 放弃当前截图 |

## 自定义截图快捷键

**右键菜单栏图标 → 偏好设置 → 录制快捷键 → 按下组合键**（例如 **⌃⇧A**）。注册成功后立即生效并自动保存。普通键需要搭配 Command、Option 或 Control，也支持单独使用 F1–F20；部分 Mac 的功能键需要按住 Fn。

按 Esc、点击其他位置、切换应用或关闭设置可取消录制。录制期间不会触发截图；注册冲突时保留原快捷键，可继续尝试其他组合。常见系统/编辑命令（例如 ⌘Q、⌘C、⌘S）不能用作截图键。原有三组预设仍可从下拉框选择，升级保留之前的选择。

录制只监听轻截当前窗口的按键，不监听其他应用；跨应用触发仍使用系统 HotKey 注册。

## 轻量设计

- SwiftUI + AppKit，系统 ScreenCaptureKit 单次静态截图，无 Electron / WebView。
- 启动不弹窗，不显示 Dock 图标；设置按需创建，关闭后释放。
- 无外部依赖、服务器、账号、遥测、网络上传、后台截图流和轮询计时器。
- 全局快捷键使用系统 HotKey API，不监听键盘内容，不要求辅助功能权限。
- 同时只处理一张截图；每张最多 200 个标注，每条画笔路径最多 20,000 个采样点。
- 完成或取消即释放截图缓存；不建立历史记录。旧版已保存的截图文件保持不变。
- 中英文跟随系统应用语言；PNG 保留截图原始像素，使用 sRGB 输出。

## 开发与验证

```bash
swift format format --in-place --recursive Sources Tests Package.swift scripts/create-icon.swift
swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
swift test
./scripts/build-app.sh
```

源码入口：`Sources/Feather/App/FeatherApp.swift`。使用 Xcode 打开 `Package.swift`；实际测试权限与菜单栏时优先运行打包的 `.app`，保持应用标识一致。

本版本聚焦区域截图与标注，不包含滚动长截图、OCR、翻译、录屏、贴图、自动窗口识别、跨显示器拼接或标注对象二次移动。截图文件由用户管理，应用不自动删除。

- [功能与界面说明](docs/FEATURES.md)
- [架构与生命周期](docs/ARCHITECTURE.md)
- [内部接口约定](docs/API.md)
- [测试与手动验收](docs/TESTING.md)
- [变更记录](CHANGELOG.md)

API 参考：[Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit)、[Apple 屏幕捕捉授权](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess%28%29)。
