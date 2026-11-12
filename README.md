# 轻截 Feather

轻量、原生的 macOS 菜单栏截图工具。框选后直接标注，快速复制或保存。

**macOS 14+ · 离线使用 · 零第三方依赖**

## 功能

- **多种截图**：区域、全屏、窗口、重复上次区域；选区可移动、缩放和撤销。
- **就地标注**：矩形、椭圆、箭头、画笔、高亮、文字、遮盖、马赛克；支持移动、删除和原位文字编辑。
- **高清输出**：保留 Retina 原始像素和色域，无损 PNG 保存、复制或贴图。
- **菜单栏常驻**：左键截图，右键设置；可自定义全局快捷键、保存目录和鼠标显示。

## 使用

1. 打开 Feather，首次截图时按系统提示允许屏幕录制权限。
2. 点击菜单栏图标或按 **⇧⌘2**，拖动选择截图区域。
3. 用悬浮工具条添加标注；画好的框可拖住边线移动。
4. **双击选区或点击 ✓** 复制并收起；点击保存或按 **⌘S** 保存为 PNG。

默认保存到 `~/Pictures/Feather`，保存后同时复制，可在设置中更改。

**自定义快捷键**：右键菜单栏图标 → 偏好设置 → 录制快捷键 → 按下新组合键。

| 快捷键 | 操作 |
| --- | --- |
| ⇧⌘2（默认，可自定义） | 开始截图 |
| 1–8 | 切换标注工具 |
| V / 0 | 切回移动选区 |
| ⌘Z / ⇧⌘Z | 撤销 / 重做 |
| ⌘S / ⇧⌘S | 快速保存 / 另存为 |
| ⌘C / Enter | 复制并收起 |
| Delete / F2 | 删除标注 / 编辑选中文字 |
| ⌘P | 贴图 |
| Esc | 取消截图 |

## 构建

需要 Xcode 16+ / Swift 6，以及用于签名的 Apple Development 或 Developer ID Application 证书。

在项目目录执行，将 `CERTIFICATE_SHA1` 替换为第一条命令列出的证书 SHA-1：

```bash
security find-identity -v -p codesigning
printf '%s\n' 'CERTIFICATE_SHA1' > .signing-identity
./scripts/build-app.sh
open dist/Feather.app
```

`.signing-identity` 已被 Git 忽略。后续构建保持同一签名身份；日常使用建议将应用放到「应用程序」文件夹，再授权。

## 文档

- [详细功能](docs/FEATURES.md) · [权限与启动排障](docs/TROUBLESHOOTING.md)
- [开发架构](docs/ARCHITECTURE.md) · [内部接口](docs/API.md) · [测试说明](docs/TESTING.md)
- [更新记录](CHANGELOG.md) · [发行流程](docs/RELEASING.md) · [MIT 许可证](LICENSE)
