# 架构与生命周期

## 模块
```text
FeatherApp / AppDelegate
├── NSStatusItem：左键截图 / 右键菜单
├── AppModel → UserDefaults（设置）
├── PreferencesView → ShortcutSettingsView（按需窗口）
├── HotKeyService → Carbon RegisterEventHotKey
├── ShortcutRecorder → 当前窗口临时 NSEvent 本地监听 → CaptureShortcut
└── CaptureCoordinator → ScreenCaptureService → ScreenCapturePipeline → ScreenCaptureKit 单次帧
    └── SelectionView：冻结画面 / 选区 / 标注
        ├── CaptureToolbar → EditorDocument
        └── FeatherCore
            ├── CaptureGeometry / SelectionGeometry
            ├── Annotation / AnnotationHistory
            ├── AnnotationGeometry / AnnotationRenderer
            └── PNGExporter
```

## 状态与窗口
- 启动设置 accessory 激活策略，不创建工作台或 Dock 图标。NSStatusItem 分发左右点击，右键时弹出 NSMenu。
- 设置窗口按需创建；关闭时释放其内容视图，录制器通过窗口通知/onDisappear 清理监听。
- 一次截图对应一个 CaptureCoordinator：截屏 → 多屏框选 → 保留目标屏覆盖层并添加工具条 → 输出或取消 → 释放。
- 框选用 screenSaver 层级，选中后降为 floating，文字和保存面板使用 modalPanel 层级。
- 重复截图聚焦现有会话，不创建第二份图像或第二组覆盖层。导出期间阻止取消与退出。
- UI、AppKit 渲染和窗口管理均为 @MainActor；ScreenCaptureKit 异步取单帧，不创建 SCStream。
- PNG 无标注时直接由 ImageIO 编码裁剪图，避免全图重绘；有标注时只合成一次，保留源 RGB 色域（非 RGB 回退 sRGB）。磁盘写入在后台 Task 完成。
- ScreenCapturePipeline 以显示器 ID、frame 和 backingScaleFactor 为缓存键，只复用按应用排除自身窗口的过滤器。无法枚举自身应用时使用当次窗口列表且不缓存；显示器变化、捕捉错误/取消后重新准备。
- 多屏静态取图使用结构化任务组并发执行，按原显示器顺序收集。所有帧完成后一次性显示覆盖层，防止捕捉到新建覆盖层；任一失败不呈现部分结果。无固定等待、没有空闲预取或常驻 SCStream。
- 快速保存先写同目录暂存文件，再用 renamex_np(RENAME_EXCL) 原子发布，拒绝覆盖，失败清理暂存文件。
- 保存成功后按设置复制，所有输出成功才关闭；失败继续保留图片、选区和标注。
- 确认按钮、键盘确认和所有工具下双击共用 EditorDocument.copy(closeAfter: true)。系统 NSEvent.clickCount 识别双击，优先于标注命中；绿框手柄优先缩放。首击产生的小标记保存变更前历史，确认时恢复，保留原有重做分支。文档默认写系统剪贴板，测试注入独立剪贴板验证实际 PNG。
- 文字工具单击启动短生命周期 MainActor Task，等待系统双击间隔后请求输入；新点击、文档状态变化或窗口移除取消 Task。没有常驻计时器或后台轮询；生产使用原生面板，测试注入文字输入器。
- 取消标志、Task 取消和 finished 保证一次会话至多回调一次。
- 激活时预检查仅更新 UI；主动截图直接调用 ScreenCaptureKit。真正 userDeclined 才显示授权恢复提示，普通捕捉失败独立处理，没有后台轮询。

## 快捷键
- 录制临时监听当前设置窗口，完成/取消/失焦立即清理；无全局按键监听或事件注入。
- 原热键在录制期间保持注册，Carbon 回调用于接受原组合，屏蔽截图动作。
- 新热键先注册成功再释放旧热键；JSON 编码和注册均成功后才更新持久化设置。
- 注册冲突保留旧组合；新旧键值比较仅使用物理键码和修饰键。

## 坐标与选区变化
- SelectionView 采用左上角原点的 flipped 坐标，显示器全局位置仅用于放置覆盖窗口。
- 截图宽高优先为 SCContentFilter.contentRect.size × pointPixelScale；无效时回退显示器逻辑大小 × backingScaleFactor。裁剪始终按实际 CGImage 尺寸分别计算 X/Y 比例，向外像素取整。
- 八个手柄固定对边，保留至少 4 逻辑点；移动保持大小，并限制到当前屏幕。
- 选区调整从原始冻结图重裁剪；标注和重做栈偏移量为「旧裁剪像素原点 − 新原点」，保持屏幕锚点。
- AnnotationGeometry 统一标注包围盒、轮廓命中、文字字体和箭头头部；按逆绘制顺序命中，Option 跳过命中。拖动保存原标注并只预览平移副本，抬起后由 EditorDocument 提交一次移动。
- AnnotationHistory 保存新增与相对移动两类记录，最多 200 步；移动记录仅保存 ID 和位移，不重复存储整条画笔路径。裁剪变化迁移当前标注和新增记录，移动记录的相对偏移保持不变。
- 标注与导出使用原图像素；预览直接绘制 CGImage 并禁用像素插值，工具条和选中标注的虚线辅助框独立于图片渲染，不进入 PNG。
- SelectionView 持有主工具条与属性卡片两个 NSHostingView；主工具条尺寸固定，属性按当前工具/导出状态按需显示。SelectionGeometry 分别约束位置，属性优先向选区外侧展开。
- CaptureStyle 提供统一选框颜色与工具条状态；小面积 HUD 使用窗口内 NSVisualEffectView 材质，不引入额外屏幕捕获、计时器或依赖。

## 内存与隐私
- 框选前暂存逐屏静态帧；选定后释放其他显示器覆盖层，保留目标屏原图以支持调整选区。
- 完成或取消关闭并释放全部截图窗口、图像和工具条；服务仅保留轻量系统过滤器，空闲时不截图、不轮询、不联网。
- 无历史列表、数据库、HTTP API、服务端、上传、自动更新器或遥测。
- 截图权限由系统 TCC 管理，不修改授权数据库。
- 未保存内容仅存在内存；Esc/×/右键选区立即放弃，退出应用也不会自动保存。

## 构建与发行
- Swift Package 构建执行文件，脚本将执行文件和本地化 bundle 装入标准 .app。
- 默认按构建机器架构生成；源码支持 arm64 和 x86_64，需分别实机验证。
- 签名从 CODE_SIGN_IDENTITY 或本机 .signing-identity 读取，默认要求固定身份；正式发行需要 Developer ID Application 和公证。
- 构建在暂存 app 内完成并验证签名，成功后替换 dist 产物，仅保留一个 .build/Feather-previous.app 回滚副本；不会原地覆写运行中的可执行文件。
- ad-hoc 仅允许显式选择并输出警告；不通过自定义宽松 designated requirement 掩盖签名变化。
- 保持 bundle ID com.feather.screenshot；稳定安装路径和签名身份可降低重新授权概率。
- 系统权限、多屏和多版本交互必须按 TESTING.md 验收。

系统配置参考：[Apple SCStreamConfiguration](https://developer.apple.com/documentation/screencapturekit/scstreamconfiguration)。
