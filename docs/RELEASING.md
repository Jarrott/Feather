# 构建与发行

## 本机开发

按 README 配置固定 Apple Development 签名身份后运行 `./scripts/build-app.sh`。更新前退出旧应用，验证时保持原安装位置。构建不会安装或修改系统权限。

`FEATHER_RELEASE=1` 只为正式发行启用 hardened runtime 和时间戳，并默认构建 arm64 + x86_64 通用二进制；正常本机构建保持既有签名方式、Bundle ID 和当前 CPU 架构。`FEATHER_UNIVERSAL=1` 可在本机构建通用二进制，`FEATHER_UNIVERSAL=0` 可让正式构建只出当前架构。

## GitHub Actions

- 日常提交前在本机运行 `./scripts/validate.sh`，完成格式、脚本语法、完整测试、6K 基准、Release 构建与签名验证。
- `macOS checks`：仅手动触发，运行相同验证脚本；push 和 PR 不再自动消耗 runner。
- CI 显式使用 ad-hoc 签名，仅验证打包，不发布可下载版本。
- `Prepare signed release`：仅手动触发。先检查已有标签与 Info.plist 版本一致，再验证、签名、公证，最后创建可审阅的 Release 草稿；不自动发布。
- 默认 runner 为 macos-15。发行构建为通用二进制，同时支持 Apple 芯片与 Intel Mac；产物按二进制实际架构命名，通用版本为 `universal`。

正式发行需要配置 GitHub 的 `release` Environment，可设置审批人员；在该环境添加以下 Secrets，勿放入仓库：

| Secret | 用途 |
| --- | --- |
| DEVELOPER_ID_P12_BASE64 | Developer ID Application 证书与私钥的 P12 编码 |
| DEVELOPER_ID_P12_PASSWORD | P12 密码 |
| DEVELOPER_ID_IDENTITY | 证书 SHA-1 或唯一完整签名身份 |
| NOTARY_APPLE_ID | 公证 Apple ID |
| NOTARY_APP_PASSWORD | Apple 应用专用密码 |
| APPLE_TEAM_ID | 发行团队 ID |

凭据导入 runner 临时钥匙串，结束时清除钥匙串和 P12。未配置凭据、签名/公证失败时不会创建发行草稿。不要把本机 Apple Development 证书误当作 Developer ID 分发证书。

版本发布顺序：

1. 更新 Info.plist、界面版本、CHANGELOG，完成测试。
2. 经维护者决定提交、推送并创建对应版本标签。
3. 手动运行发行工作流，输入已有标签，例如 `v1.4.0`。
4. 检查草稿中 ZIP、SHA-256、平台架构和说明，再发布。

## 本机公证打包

已通过 `notarytool store-credentials` 在本机钥匙串保存公证资料后：

```bash
CODE_SIGN_IDENTITY='Developer ID Application: YOUR_NAME (TEAM_ID)' FEATHER_RELEASE=1 ./scripts/build-app.sh
NOTARY_PROFILE='YOUR_KEYCHAIN_PROFILE' ./scripts/package-release.sh
```

打包脚本验证 Developer ID 签名，提交公证、装订凭证并执行 Gatekeeper 检查，输出 `dist/Feather-版本-架构.zip`（通用二进制为 `universal`）与校验文件；不会推送 Git 或自行发布。尚未完成正式公证的应用不能宣称已可直接对外分发。

参考：[GitHub macOS runner](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)、[gh release create](https://cli.github.com/manual/gh_release_create)。
