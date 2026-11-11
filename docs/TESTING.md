# 验证与回归

## 自动化
```bash
swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift
swift test
./scripts/build-app.sh
codesign --verify --strict dist/Feather.app
```

Swift Testing 覆盖：双向拖拽、Retina 比例、非整数像素和显示器负原点；八个手柄定位、缩放最小尺寸、移动边界、工具条屏内布局；撤销/重做和裁剪后坐标迁移；七种标注真实 PNG 渲染、上下方向、遮盖像素替换、高亮透明度；文件唯一性与无效目录；快捷键录制、校验、旧偏好兼容、注册失败保持原值及取消生命周期。

## 手动验收
每次修复后及版本升级需回归对应项。未执行的项目不能标记通过。

| 场景 | 期望 |
| --- | --- |
| 启动 / 重启 | 只出现菜单栏图标，无工作台、Dock 图标或独立编辑窗口 |
| 菜单栏左键 / 右键 | 左键截图，右键菜单可进入设置；Control+点击同右键 |
| 首次无权限 | 截图时提示系统权限，取消不产生文件；授权后可重新截图 |
| 框选 | 冻结画面，松开后原处显示选区和一排悬浮按钮，无设置窗口残影 |
| 移动 / 八个手柄 | 限制屏幕范围、最小 4 点；像素尺寸准确，标注保持屏幕锚点 |
| 靠近边缘 / 全屏选区 | 主工具条和属性卡片保持屏内；底边选区的属性优先朝上展开，不进入导出的图片 |
| Esc / 右键选区 / × | 直接放弃当前截图，所有覆盖层退出，菜单栏仍可再截图 |
| Retina / 外接屏在左上方 | 输出像素与提示一致，方向正确，裁剪无偏移 |
| 混合 DPI 双屏 | 两块屏幕均可独立框选，像素大小准确；选中后释放另一屏覆盖层 |
| 显示器拔插 | 非导出状态取消当前会话，不遗留覆盖窗口 |
| 其他应用全屏空间 | 全局键可发起截图，关闭后恢复之前空间 |
| 标注工具 | 七种工具可就地绘制，选中工具才显示独立属性卡片；主工具条不跳动；文字支持中文输入法和粘贴 |
| 工具状态 | 悬停、选中和禁用可区分；再次点击当前工具回到移动模式，1–7 连按仍为绘图模式 |
| 撤销 / 重做 | 顺序准确；移动/缩放选区后坐标仍正确，新标注清空重做分支 |
| 保存 / ✓ / Enter | PNG 包含全部标注，成功后收起；剪贴板可粘贴到其他应用 |
| 保存路径无权限 | 显示错误，保留选区和标注；另存到可写位置后成功收起 |
| 另存为取消 / 覆盖确认 | 取消保留会话，不写入；覆盖只在系统确认后发生 |
| 快捷键录制 | 新组合立即生效并重启保留；常见系统/编辑命令提示不可用 |
| 录制取消 / 冲突 | Esc、外点、失焦或关设置取消；冲突时旧组合仍可用 |
| 重复截图 / 保存 | 聚焦同一选区，不创建多次会话或并行写入 |
| 中英文 | 精简设置、工具条提示、菜单和错误文案显示完整 |

## 1.2.0 执行记录
2026-11-11，Apple Silicon：

- `swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift`：通过。
- `swift test`：46 项通过（24 个核心 + 22 个应用测试）；新增属性浮层在偏移屏幕、底边、窄屏的边界/换侧验证，以及工具重复点击、数字键选择语义、导出锁定与标注保留验证。
- `FEATHER_PREVIEW_DIR="$PWD/.build/previews" swift test` 生成实际视图离屏图；已人工查看默认选区、标注属性、底边、全屏、600 点窄屏及导出错误状态。底边属性卡片优先展开在工具条上方。
- `./scripts/build-app.sh`：Release 构建通过，1.2.0 (4)，arm64，约 1.4 MB；可访问系统钥匙串的环境中 `codesign --verify --strict --verbose=2` 通过。
- 新旧包的 `codesign -d -r-` 输出完全一致，沿用用户指定的固定 Apple Development 证书；未重置权限，未修改截图授权或快捷键注册逻辑。
- Info.plist、132 个中英文资源键/占位符、源码行数和 `git diff --check` 校验通过。
- 确认旧应用无可见窗口后正常退出，并打开当前 `dist/Feather.app`。通过 orca-computer-use 读取实际设置窗口，确认版本 1.2.0、自定义 ⌃⌘A 已注册、截图权限已就绪。检查结束时进程仍运行，未遗留可见窗口。
- 自动化发送全局热键未获得可验证的截图选区结果，未据此判定应用故障，也不将真实鼠标绘制、悬停、跨应用热键或本版本实屏输出标记为通过；这些项目仍需用户实际按键验收。离屏测试不读取桌面、不改剪贴板或 TCC。

新增预览文件：bottom-edge.png、fullscreen.png、narrow.png、export-error.png；生成命令沿用下方离屏渲染说明。产物均位于忽略的 `.build/`，不进入 Git。

## 1.1.1 执行记录
2026-11-11，Apple Silicon：

- `swift format lint --strict --recursive Sources Tests Package.swift scripts/create-icon.swift`、`bash -n scripts/build-app.sh`：通过。
- `swift test`：44 项通过（23 个核心 + 21 个应用测试）；新增预检查为 false 仍调用系统提供器、严格识别拒绝错误、实际拒绝更新状态、普通错误保持状态、取消后不显示延迟授权错误五项回归。
- `./scripts/build-app.sh`：Release 构建和签名验证通过，产物 1.1.1 (3)，arm64，约 1.3 MB。
- `codesign -d -r-` 确认 designated requirement 已使用 Apple 证书和应用标识，不再是旧 ad-hoc 的单一 cdhash。证书由用户指定，本机配置已忽略。
- `git check-ignore -v` 确认构建目录、截图预览、应用包、.signing-identity、环境文件、证书/私钥及个人状态被排除。
- Info.plist 与 128 个中英文资源键、占位符一致性检查通过。
- 权限测试使用注入提供器，不申请系统权限、不读桌面、不修改 TCC。原生 UI 连接再次失败，真实授权切换、签名升级后的重新授权和截图仍待用户实机验收。
- 本次按用户明确要求初始化 Git 并发布源码；以下旧版本“未初始化/未提交”记录为当时状态。

新增手动回归：旧副本已授权 → 固定开发证书构建 → 退出旧版 → 为当前 app 重新授权 → 重启 → 截图；以后以同一证书构建时检查权限是否延续。真实系统拒绝仍必须显示修复提示，不能靠缓存把未授权状态当作成功。

## 1.1.0 执行记录
2026-11-11，Apple Silicon / macOS 27.0.1 / Swift 6.4：

- 格式检查通过：swift format lint --strict，覆盖 Sources、Tests、Package.swift 和图标脚本。
- swift test 通过：23 个核心测试 + 16 个应用测试，共 **39 项**。
- 应用测试使用隔离偏好；覆盖实际 PNG 写入、保存成功只关闭一次、保存失败保留标注且不关闭、更换目录重试成功后关闭。
- 选区交互测试直接将 NSEvent 对象传给未显示的自有视图，验证框选、移动、缩放、绘图、撤销和右键取消。没有向系统注入事件。
- 快捷键测试覆盖自定义组合、JSON 往返、旧预设回退、非法/保留键、注册失败、有效输入消费、Esc/失焦/外点取消、重复键和保留原组合。
- 原生离屏渲染通过，已人工检查精简设置、单排工具条、展开标注选项的工具条与导出图；不显示测试窗口、不截图、不改用户剪贴板。
- ./scripts/build-app.sh Release 构建通过，arm64 dist/Feather.app **约 1.2 MB**，版本 1.1.0 (2)，本地 ad-hoc 签名验证通过。
- Info.plist、脚本语法和本地化资源校验通过；中英文 127 个键一致，源文件均少于 1000 行。
- 基于修改前快照审阅源码差异，git diff --no-index --check 无空白错误；本目录仍未初始化 Git，未自动 commit/push。

预览重建：
```bash
FEATHER_PREVIEW_DIR="$PWD/.build/previews" swift test --filter nativeViewsRenderOffscreen
```
产物为 settings.png、selection.png、overlay.png 和 annotated-export.png。

未完成真实屏幕交互验收：原生电脑操作工具连接失败（Sky Computer Use native pipe startup failed）。因此菜单栏真实左右点击、首次系统授权、跨应用全局热键、真实鼠标框选、剪贴板跨应用粘贴、全屏空间及混合 DPI 双屏仍需按上表实机验证。macOS 14 与 Intel 机器尚未实机测试；最低部署目标为 macOS 14。

## 历史修复回归
- 1.0.0：Foundation 不支持组合 atomic/withoutOverwriting，保存已改为同目录暂存加 renamex_np(RENAME_EXCL)；本版文件唯一性、实际写入和失败重试继续通过。
- 目录恢复保留 URL 的目录语义，偏好重建测试继续通过。
- PNG 颜色断言使用原始通道，避免 NSColor ICC 舍入造成假失败。
- 1.1.0：新热键先注册再替换，防止冲突丢失旧键；裁剪变化同步平移重做栈，防止恢复标注错位。

## 旧授权签名不匹配排查（2026-11-11）

- 实机确认运行中的 1.1.1 来自 dist/Feather.app，开发证书与构建一致。
- tccd 日志明确出现 Failed to match existing code requirement，残留授权要求为旧 ad-hoc cdhash，当前应用要求为固定 Apple Development 证书。开关打开并不代表该旧记录能匹配当前副本。
- 使用 orca-computer-use 按 PID 读取菜单栏应用的设置窗口，确认自定义热键已注册；按 bundle ID 的应用列表不含此 accessory 应用，需要使用实际进程 PID。
- 用户明确同意后，正常退出应用并执行 tccutil reset ScreenCapture com.feather.screenshot，命令报告成功，再通过当前 app 的绝对路径重新打开。未修改 TCC 数据库、未重置其他应用权限。
- 用户完成系统重新授权和重开后，确认 ⌃⌘A 已出现截图选区；本次实际权限故障恢复。未将本次恢复扩大为其他屏幕缩放、导出或系统版本的验收结果。
