# 架构与生命周期

## 模块

```text
AppDelegate / AppModel → 菜单栏、快捷键、设置、SavedRegion
├── CaptureCoordinator → ScreenCaptureService → ScreenCaptureKit 单次帧
│   ├── ScreenCapturePipeline：多屏并发、轻量过滤器缓存
│   └── SelectionView：冻结图、编辑文档、工具条布局
│       ├── SelectionInteraction：单一活动手势状态
│       ├── SelectionRendering：CALayer 冻结图、遮罩、局部动态绘制
│       ├── SelectionInput：键盘映射、VoiceOver 动作
│       └── InlineTextEditor：原生文本输入与提交
├── WindowCapturePicker：用户选择窗口，无缩略图预取
├── EditorDocument → 后台渲染/编码/写入 → 主线程输出状态
│   ├── FeatherCore：坐标、历史、CoreText、PNG、文件名模板
│   └── PasteboardWriter：备份、替换、条件恢复
└── PinnedImageController：最多八张内存贴图
```

## 并发与导出

- AppKit 窗口、输入、设置与剪贴板在 MainActor 上；`EditorDocument` 同步锁定导出并快照 CGImage、值类型标注和输出设置。
- `Task.detached` 执行全部合成、编码和写盘，完成后返回 Data/URL/CGImage。导出期间禁止编辑、重复输出和退出，失败保留会话。
- 渲染内核不依赖 AppKit，不标记 MainActor；文字使用 CoreText。每次测量/绘制创建独立排版对象，不跨线程复用 CTFrame/CTFramesetter。
- 无标注 PNG 直接 ImageIO 编码原图；有标注时在源 RGB 色域合成一次。马赛克仅降采样指定区域，并尊重纯黑遮盖区域。
- 贴图复用 `AnnotationRenderer.composite` 直接取得位图，不做 PNG 编解码往返；窗口设置 `hidesOnDeactivate = false`，切换应用仍可对照。
- 剪贴板先准备新项目与最多 64 MiB 的原内容快照；备份失败即返回。写入失败后仅在 changeCount 未变化时恢复，避免覆盖其他应用的新内容。恢复是尽力而为，系统接口无跨进程原子事务。

## 捕捉和会话

- 捕捉由用户触发，系统每次检查权限。仅 `SCStreamError.userDeclined` 更新为拒绝；普通错误、取消不改变权限状态。
- 启动权限状态未知，不读取 `CGPreflightScreenCaptureAccess()`；无后台权限轮询。
- 旧版 SDK 未为 SCShareableContent 标注 Sendable，服务文件使用 `@preconcurrency import ScreenCaptureKit` 兼容；返回的只读快照仅在 MainActor 读取，不增加共享可变状态或关闭全局并发检查。参见 [Swift SDK 迁移说明](https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/incrementaladoption/)。
- 多屏通过结构化任务组并行取静态图，按原屏幕顺序组装；过滤器以 ID/frame/缩放为缓存键，屏幕变化、失败或取消使其失效。缓存不包含图像或授权。
- 窗口截图使用 desktopIndependentWindow 过滤器，不等同于桌面裁剪。用户选择窗口后才取图；窗口关闭导致的错误走统一失败流程。
- 框选前屏幕参数变化取消请求；编辑中落定手势/文字并保留原始 CGImage 与历史，窗口等比例适配可用屏幕。没有屏幕时等待恢复，不重新采集。
- 覆盖层保持 screenSaver 层级，另存为面板高一层；区域内内联文本不需要模态窗口。
- 会话只结束一次。成功输出记录上次显示器 ID/归一化区域，窗口截图除外；取消不覆盖上次成功区域。

## 绘制与坐标

- SelectionView 使用左上原点的屏幕局部逻辑点；标注和裁剪历史使用原图像素。
- 截图尺寸为系统内容点尺寸 × 像素比例；裁剪向外取整，对接近整数的浮点误差先对齐，避免重复区域逐次膨胀。
- FrozenImageView 一次将源图交给 CALayer.contents；CAShapeLayer 只更新遮罩孔洞，禁止隐式动画。
- AnnotationCanvasView 是透明动态层。按新旧标注/预览/选中边界计算脏区，只渲染与脏区相交的标注。选区变化才更新遮罩和尺寸。
- 文本布局、命中包围盒和导出共用 TextLayout；输入使用 NSTextView，存储独立像素字号。预览输入字体换算为逻辑点。
- SelectionInteraction 将起点、原选区和预览标注打包到互斥枚举状态；双击首击历史及延迟文字任务单独管理，切换/输出/窗口关闭取消待输入任务。

## 编辑历史与持久化

- AnnotationHistory 统一记录新增、相对移动、带原层级的删除、前后文字替换及前后裁剪矩形，最多 200 步。
- 裁剪拖动期间预览，抬起后记录一步；当前标注和历史中的绝对坐标同步平移，相对移动和全图裁剪矩形不变。
- 撤销裁剪根据源 CGImage 重新切片，不持有每一步全屏副本。选择辅助线、输入框不属于标注输出。
- UserDefaults 仅存设置、快捷键 JSON 和上次区域几何。截图/标注/贴图只在内存，保存才写 PNG。
- 文件名模板验证占位符与单文件名边界；同目录暂存 + renamex_np(RENAME_EXCL)，重名最多重试 1,000 次。

## 构建和发行

- Swift Package，无第三方依赖，macOS 14+。Bundle ID 保留 `com.feather.screenshot`，避免无必要的权限身份迁移。
- 默认读取本机 `.signing-identity` 或 CODE_SIGN_IDENTITY，固定签名；暂存应用完成签名验证后再替换 dist，只保留一个回滚副本。
- 日常执行 `scripts/validate.sh` 在本机验证；Actions 仅手动触发，复用同一脚本并显式使用 ad-hoc 验证构建，不将其当作正式发行。
- 本机默认当前 CPU 架构；正式发行默认 arm64 + x86_64 通用二进制，打包名称取自实际二进制架构。
- 正式发行单独启用 hardened runtime/时间戳，要求 Developer ID 签名、公证、staple 和 Gatekeeper 验证；人工触发工作流创建 Release 草稿。详见 [发行说明](RELEASING.md)。

参考：[Apple CoreText 线程规则](https://developer.apple.com/documentation/CoreText)、[SCContentFilter](https://developer.apple.com/documentation/screencapturekit/sccontentfilter)。
