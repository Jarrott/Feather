# Feather 项目开发约定

## 项目与范围
- 轻量 macOS 14+ 截图工具；Swift 6、SwiftUI、AppKit、ScreenCaptureKit，零第三方依赖。
- 开发前阅读 README.md、docs/FEATURES.md、docs/ARCHITECTURE.md、docs/API.md 和 CHANGELOG.md。
- 不引入 Web 容器、服务端、账号、遥测或常驻截图流。
- 所有截图仅在用户触发时产生；权限由系统管理，不绕过授权。
- 重要方法使用中文 Swift 文档注释；用户界面文案集中在中英文 Localizable.strings。
- 用户未明确要求时，不自动提交或推送 Git；不操作其他项目。
- 构建使用固定签名身份；本机 .signing-identity 必须忽略，不提交证书、私钥或环境配置。

## 结构
- Sources/FeatherCore：可测试的坐标、标注、渲染和文件导出。
- Sources/Feather：应用生命周期、截图与标注覆盖层、菜单栏、设置与原生界面。
- Tests/FeatherCoreTests：裁剪、标注历史、渲染与导出回归测试。
- Tests/FeatherAppTests：隔离偏好、快捷键录制、选区交互、保存/重试和离屏渲染。
- scripts/build-app.sh：构建并签名本地 app；产物不进入版本控制。

## 验证
1. `swift format lint --strict --recursive Sources Tests Package.swift`
2. `swift test`
3. `./scripts/build-app.sh`
4. 按 docs/TESTING.md 执行可运行的界面/权限验证，清楚标记未测项。
5. 检查 diff、文档、注释和本地化一致性。空目录未初始化 Git 时不伪造 diff 结果。

## 回归重点
- Retina 裁剪不倒置、不降采样；多屏坐标独立，单次选区不跨屏。
- Esc 取消不落盘；画笔/文字/撤销/重做与导出使用一致坐标。
- 保存失败保留选区和标注；快捷键注册冲突可见且保留原设置。
- 启动不弹窗，设置关闭后菜单栏继续可用；重复触发截图不能叠加覆盖层。
- 八个手柄和移动选区不越界；裁剪变化同步平移当前标注与重做栈，保持原屏幕锚点。
- 保存或复制成功收起，失败保留会话；Esc/×/右键选区直接放弃，无自动保存。
- 权限预检查不能拦截主动截图；只按系统 userDeclined 识别授权拒绝，普通错误和取消不能混报。
- 主工具条保持单排；属性浮层优先避开选区并留在屏内。工具按钮可取消选中，数字键不可意外切回移动模式；导出期间禁止切换。
- 移动模式双击选区内部与确认按钮共用复制并关闭流程；绘图、选区外、缩放手柄和导出期间不得误确认。剪贴板测试使用独立实例，不覆盖用户内容。
