# 内部接口约定

纯本地 macOS 应用，无 HTTP API 或数据库。内核错误保持英文，界面通过本地化映射展示。

| 模块 / 接口 | 输入与返回 | 调用方 / 约束 |
| --- | --- | --- |
| CaptureGeometry.capturePixelSize / pixelRect | 系统点尺寸/缩放 → 原生像素大小；逻辑选区 → CGRect? | 捕捉、编辑；向外取整并消除近整数误差，无效输入 nil |
| SelectionGeometry.move / resize / toolbarFrame / optionsFrame | 原选区、位移、边界 → CGRect | 覆盖层；选区最小 4 点，浮层限制屏内 |
| Annotation | UUID、tool、像素 points、InkColor、lineWidth、text、fontSize | 值类型 Sendable；文字 ≤2,000，字号独立，构造限制 8–240 |
| AnnotationTool.shortcut / forShortcut | 工具 → 固定字符串；按键 → 工具? | 数字 1–8 明确绑定，新增工具不重排原有键 |
| AnnotationGeometry.bounds / contains / constrainedOffset | 标注/像素点/容差 → 几何结果 | 命中、脏区、拖动；与 TextLayout 共用测量 |
| TextLayout.size / draw | 标注 → CGSize / CGContext 绘制 | 无 MainActor；每次调用独立创建 CoreText 排版对象 |
| AnnotationRenderer.draw / png | 标注、上下文、可选源图和遮盖区域 / CGImage、标注数组 → Data | 纯后台安全内核；源 RGB 色域，PNG 无损；失败抛 ExportError |
| AnnotationHistory.append / move / remove / replace | 标注或 ID/偏移 → Bool | 无效或无变化返回 false；新增、移动、删除、文字替换统一进历史 |
| AnnotationHistory.previewCrop / commitCrop | 当前/起始全图像素矩形 | 拖动预览平移坐标，完成仅记录一次裁剪；undo/redo 同步恢复 |
| FilenameTemplate.validated / filename | 模板/日期/像素尺寸/随机 ID → String | 仅白名单变量，不允许路径或控制字符，非法抛 invalidFilename |
| PNGExporter.save | PNG Data、目录、模板、尺寸、可选时间 → URL | 同目录原子发布，不覆盖；碰撞追加编号，最多 1,000 次 |
| CaptureShortcut.validated / recorded | 键码/修饰键/名称或 NSEvent → Codable 值 | 设置录制，拒绝无效和保留组合 |
| HotKeyService.register / AppModel.registerShortcut | 新组合、注册闭包 → Void / Bool | 先注册并编码成功再持久化；失败保留旧设置 |
| ScreenCapturePipeline.capture | CaptureDisplay 数组、showCursor → 新 CGImage 数组 | 并发保持顺序；过滤器缓存无图像/授权，异常或取消失效 |
| ScreenCaptureService.capture / availableWindows / capture(window:) | showCursor / 无 / SCWindow、showCursor → 快照数组 / 窗口列表 / CGImage | 全部仅用户触发；系统授权/窗口消失等错误原样传播 |
| CaptureCoordinator.start / screenParametersChanged / cancel | 模式/可用屏幕 → 生命周期回调 | 未框选屏幕变化取消；编辑时保留源图和历史，禁止取消导出 |
| SavedRegion.rect | 显示器 ID、归一化 CGRect、目标尺寸 → CGRect? | 重复上次区域，拒绝越界、非有限值及断开屏幕 |
| SelectionView.beginEditing | EditorDocument、像素 CGRect | 绑定源图、工具条和局部绘图；文字提交通过文档回调协调 |
| EditorDocument.configureCrop / previewCrop | 源 CGImage/像素 CGRect | 历史裁剪改变后从源图重建 image，不存历史图像副本 |
| EditorDocument.copy / save / pin | closeAfter、asNewLocation → 异步 exportTask | 同步锁定，快照后后台渲染/编码/写盘；主线程更新状态、剪贴板/窗口 |
| EditorDocument.undo / redo / deleteAnnotation | 无 / 标注 ID | 工具条、按键、读屏共用编辑历史；导出期间拒绝 |
| PasteboardWriter.write | PNG Data、NSPasteboard、可选写入器 → Bool | 先完整备份，失败且无外部接管才恢复；超 64 MiB 拒绝清空 |
| PinnedImageController.pin | CGImage、AppModel → Bool | 最多八张内存贴图；导出期间禁止关闭或终止应用 |

## 偏好与格式

- saveDirectory：目录路径，默认 `~/Pictures/Feather`；copyAfterSave 默认 true，showCursor 默认 false。
- filenameTemplate：默认 `Feather_{date}_{time}_{uuid}`；支持 date/time/timestamp/uuid/width/height。旧设置缺失时使用默认值。
- lastRegion：Codable `{displayID: UInt32, normalizedRect: CGRect}`；只存几何，不存屏幕图像。失败或取消不更新。
- customShortcut：JSON `{keyCode: UInt32, modifiers: UInt32, keyLabel: String}`；兼容旧预设，默认 ⇧⌘2。
- 原图、标注与导出均保留原生像素；逻辑点仅用于窗口交互。默认无压缩损失 PNG，源 RGB 色域保留，非 RGB 合成回退 sRGB。
- 错误：renderFailed / invalidPNG / invalidDirectory / invalidFilename；界面由 EditorDocument.message 映射，未知系统错误用系统本地化描述。

## 兼容性

- 1.1.1 起实际捕捉验证权限；1.4.0 激活和初始化也不再使用预检查，初始状态未知。
- 1.3.0 支持拖动标注和全部工具双击确认；1.4.0 保留，并新增删除、文字编辑与裁剪历史。
- 1.3.1 原生像素、广色域与并发多屏保留；1.4.0 导出异步完成，测试/调用方应等待 exportTask 或 onClose，不假定 copy 同步完成。
- Bundle ID、旧快捷键、保存目录保持兼容；不重置授权，不删除用户截图。
