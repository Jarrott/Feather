# 内部接口约定

本项目为纯本地 macOS 应用，无 HTTP API、远程调用方或数据库。以下为模块间接口，不对外发布网络服务。导出内核错误使用英文，界面文案使用中英文本地化资源。

| 接口 | 输入 | 输出 / 规则 | 调用方 |
| --- | --- | --- | --- |
| CaptureGeometry.capturePixelSize | 系统内容点尺寸、像素比例、屏幕尺寸与 backingScale | 向上取整的原生像素 CGSize?；无效系统值回退屏幕几何，两者无效返回 nil | ScreenCaptureService、测试 |
| CaptureGeometry.selection / pixelRect | 逻辑点、边界 / 选区和图像大小 | 边界内选区 / 像素 CGRect? | SelectionView、CaptureCoordinator、测试 |
| SelectionHandle.point | 逻辑选区 | 八个角点/边中点之一 | SelectionView、测试 |
| SelectionGeometry.move / resize | 原选区、偏移、边界、可选手柄 | 限制边界、最小 4 点的逻辑选区 | SelectionView、测试 |
| SelectionGeometry.toolbarFrame | 选区、工具条大小、屏幕边界 | 下方、上方或屏内的布局 CGRect | SelectionView、测试 |
| SelectionGeometry.optionsFrame | 工具条 CGRect、浮层大小、屏幕边界、preferAbove（默认 false） | 优先指定一侧，空间不足时换侧并限制在屏内；不移动工具条 | SelectionView、测试 |
| Annotation | 工具、像素点、颜色、线宽、文字 | 值类型；文字 ≤2000，线宽 1–80 | 标注覆盖层、测试 |
| Annotation.translated | 像素偏移 CGPoint | 新 Annotation，保留身份、样式和文字 | SelectionView、AnnotationHistory、测试 |
| AnnotationGeometry.bounds / contains / constrainedOffset | Annotation、像素点与容差 / 位移及图片边界 | 包围盒 / Bool / 约束后的偏移；无状态修改 | SelectionView、测试 |
| AnnotationGeometry.textFont / arrowHead | Annotation | 与命中逻辑一致的 NSFont / CGPath | AnnotationRenderer、测试 |
| AnnotationHistory.append / undo / redo | Annotation / 无 | 新增 Bool，最多 200 个标注、最近 200 步新增/移动；维护撤销/重做顺序 | EditorDocument、工具条、SelectionView、测试 |
| AnnotationHistory.move | UUID、原图像素偏移 CGPoint | Bool；无效 ID、非有限或零偏移返回 false；移动作为一步历史，保留顺序 | EditorDocument、测试 |
| AnnotationHistory.translate | 原图像素偏移 CGPoint | 同步平移当前标注及新增历史记录，移动相对偏移不变，保留 ID | EditorDocument、测试 |
| AnnotationRenderer.draw / png | 标注、上下文 / CGImage 和标注 | 绘制 / PNG Data；无标注直接编码，有标注保留源 RGB 色域，失败抛 ExportError | SelectionView、EditorDocument、测试 |
| PNGExporter.save | PNG Data、目录、可选日期 | 唯一文件 URL；写入失败抛错 | EditorDocument 后台任务、测试 |
| CaptureShortcut.validated / recorded | 键码、修饰键、名称 / NSEvent | 校验后的 Codable 值；不支持或保留组合抛错 | 录制器、解码器、测试 |
| HotKeyService.register | CaptureShortcut | 同值无操作；成功替换，失败保留旧注册 | AppDelegate |
| AppModel.registerShortcut | CaptureShortcut、注册函数 | Bool；先编码、注册，再保存；失败不变 | AppDelegate、测试 |
| ShortcutRecorder.start / cancel | AppModel、目标 NSWindow / 无 | 启停本地监听，清理观察者；无全局键盘监听 | ShortcutSettingsView、测试 |
| CaptureDisplay / CapturePlan | 显示器 ID、位置/尺寸、缩放 / 捕捉闭包数组与 reusable | 缓存键 / 按显示器顺序的 MainActor 静态捕捉入口；不持有图像 | ScreenCaptureService、ScreenCapturePipeline、测试 |
| ScreenCapturePipeline.capture | CaptureDisplay 数组、showCursor | 按输入顺序返回新 CGImage 数组；并发取图，任一失败整批抛错并清缓存；每次保留真实权限检查 | ScreenCaptureService、测试 |
| ScreenCaptureService.configuration | 像素尺寸、showCursor | 最佳源分辨率、BGRA、原显示器色域的 SCStreamConfiguration；像素尺寸由 capturePixelSize 校验 | ScreenCaptureService、测试 |
| ScreenCaptureService.capture / isPermissionDenied | 是否包含鼠标 / Error | 静态屏幕快照数组 / 严格匹配 SCStreamErrorDomain 与 userDeclined | CaptureCoordinator、AppDelegate、测试 |
| CaptureCoordinator.start / focus / cancel | 初始化参数 AppModel、可注入截图提供器 | onComplete() / onError(Error)；会话内持有文档 | AppDelegate |
| SelectionView.init | CGImage、逻辑 frame、可选 MainActor 文字输入器 | 创建冻结画面；默认原生文字面板，测试可注入返回 String?，取消返回 nil | CaptureCoordinator、测试 |
| SelectionView.beginEditing | EditorDocument、裁剪像素 CGRect | 在同一覆盖层添加工具条，观察状态变化 | CaptureCoordinator、测试 |
| EditorDocument.init | CGImage、AppModel、pasteboard（默认 .general） | 创建截图会话；可注入独立剪贴板用于隔离测试，初始化无输出副作用 | CaptureCoordinator、测试 |
| EditorDocument.updateCrop | 新 CGImage、标注像素偏移 | 更新图片和历史坐标；导出中拒绝修改 | SelectionView |
| EditorDocument.selectTool | AnnotationTool、toggleSelection（默认 false） | 按钮可再次选中同一工具以返回移动模式；数字键只选择工具；导出中无操作 | CaptureToolbar、SelectionView、测试 |
| EditorDocument.moveAnnotation | UUID、原图像素偏移 CGPoint | 一次拖动提交一步历史；导出中或无效位移无操作，成功后清除过期输出状态 | SelectionView、测试 |
| EditorDocument.save / copy | asNewLocation、closeAfter / closeAfter | 成功按参数 onClose；失败保留会话，发布错误 | 工具条、SelectionView、测试 |

## 数据格式
- 显示器位置、选区几何使用 macOS 逻辑点；标注、导出尺寸使用原图像素，不混用。
- 标注颜色为 sRGB Double 分量，范围 0...1，无任意动态容器；输出图片保留源 RGB 颜色配置，渲染器负责把标注颜色转换到目标色域。
- 导出固定 PNG；快速保存名 `Feather_yyyy-MM-dd_HH-mm-ss-SSS_<8位随机标识>.png`。
- 默认目录 `~/Pictures/Feather`，缺失时创建；无权限或不可写则保留会话并显示错误。
- 本地偏好：saveDirectory（目录路径）、copyAfterSave（默认 true）、showCursor（默认 false）。
- `customShortcut` 为 JSON Data：`keyCode: UInt32`、`modifiers: UInt32`（Carbon ⌃⌥⇧⌘ 位掩码）、`keyLabel: String`。构造和解码校验，名称不参与身份比较。
- 无资金、角色权限、业务接口、SQL；路由、Migration、数据库性能规范不适用。

## 错误和兼容性
- 导出内核：renderFailed、invalidPNG、invalidDirectory；文件系统错误保留原 NSError 信息。
- 启动优先读取有效 customShortcut，否则读取旧 shortcut 预设字符串，最后回退 ⇧⌘2。旧键保留，注册失败不写入候选值。
- 1.1.0 不再使用最近记录偏好，旧值被忽略；不删除或修改用户已有图片。
- 同一会话中的选区调整和标注仅存在内存；取消直接释放，没有自动保存或恢复。
- 保存/确认按钮、键盘和所有工具下双击调用方均明确传入 closeAfter: true；系统保存面板取消和导出失败不会调用 onClose。

- 1.1.1：权限预检查仅用于设置状态提示，不阻断主动截图；实际拒绝将状态置为未授权，普通错误不改权限，已取消请求的延迟错误不弹提示。
- 1.2.0：工具属性使用独立浮层，未修改截图提供器、权限处理、全局快捷键注册或偏好数据格式。
- 1.2.1：移动模式双击选区内部复用 EditorDocument.copy(closeAfter: true)，不新增输出格式；剪贴板可在初始化时注入，现有调用方默认行为不变。
- 1.3.0：双击确认扩展到所有工具，标注可原位拖动；新增历史记录类型在内存中使用，不改变用户偏好、截图权限或 PNG 格式。
- 1.3.1：无新增用户偏好。捕捉由串行改并行，过滤器可复用；PNG 仍保持原像素大小，颜色配置从固定 sRGB 改为源 RGB 色域。
