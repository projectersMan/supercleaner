# SuperCleaner 站外分发操作清单

适用目标：不进入 Mac App Store，通过官网、GitHub 或其他 HTTPS 渠道，让普通用户正常下载、安装和更新。

本流程使用 `Developer ID Application`、Apple 公证与 Sparkle，不使用 Mac App Store、App Review、Mac App Distribution 或 App Store 沙箱。唯一应用交付物是包含 `.app` 和 `/Applications` 快捷方式的拖放式 DMG；首次安装和 Sparkle 更新共用它，不需要 `Developer ID Installer` 证书。

详细依据和风险说明见 [`research/production-release-acceptance.md`](research/production-release-acceptance.md)。

## 0. 当前停止条件

以下任一项未完成时，不得对普通用户发布：

- [ ] 已补齐生产规则包的密钥生成、签名、envelope 输出和回读验证工具。当前仓库只有验证端，这是完整发布配置的代码阻断项。
- [ ] 已确定正式 Bundle ID、10 位 Team ID 和长期拥有的 HTTPS 域名。
- [ ] 已确定发布架构：仅 Apple silicon、Universal，或分架构发布。当前默认构建只包含构建机架构。
- [ ] 已准备一台不同于开发机的干净测试 Mac/VM，至少覆盖最低支持版本 macOS 13，并建议增加一个当前 macOS。

## 1. 一次性 Apple 身份准备

- [ ] Apple Developer Program 会员有效；具备创建 Developer ID 证书的权限。
- [ ] 安装完整 Xcode，并切换到它：

  ```bash
  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
  xcodebuild -version
  ```

- [ ] 创建并安装 `Developer ID Application` 证书及对应私钥。
- [ ] 确认证书在登录钥匙串中可用：

  ```bash
  security find-identity -v -p codesigning
  ```

- [ ] 记录证书 SHA-1；后续通过 `SUPERCLEANER_SIGN_IDENTITY` 固定使用。
- [ ] 确认证书名称中的 Team ID 与正式配置完全一致。
- [ ] 对证书私钥做加密备份并限制访问；不得提交到仓库。

验收：输出中存在 `Developer ID Application: ... (TEAMID)`，并且不是 Apple Development、Mac App Distribution 或 ad-hoc 身份。

## 2. 一次性公证凭据准备

- [ ] 创建并验证 `notarytool` Keychain profile。交互式输入密码，不把密码写入 shell 历史：

  ```bash
  xcrun notarytool store-credentials "SuperCleaner-Notary" \
    --apple-id "YOUR_APPLE_ID" \
    --team-id "YOUR_TEAM_ID"

  xcrun notarytool history --keychain-profile "SuperCleaner-Notary"
  ```

- [ ] 将 profile 名称记录为 `SUPERCLEANER_NOTARY_PROFILE=SuperCleaner-Notary`。
- [ ] 不在仓库、公开配置或 CI 日志中保存 Apple ID 密码、app-specific password 或 API 私钥。

验收：`notarytool history` 能完成认证，不出现凭据或 Team ID 错误。

## 3. 一次性 Sparkle 密钥准备

- [ ] 使用仓库固定 Sparkle 版本生成独立生产密钥：

  ```bash
  SPARKLE_BIN="$PWD/.build/release-scratch/artifacts/sparkle/Sparkle/bin"
  "$SPARKLE_BIN/generate_keys" --account "SuperCleaner-Production"
  "$SPARKLE_BIN/generate_keys" --account "SuperCleaner-Production" -p
  ```

- [ ] 将第二条命令输出的 base64 公钥记录为 `applicationPublicKey`。
- [ ] 设置 `SUPERCLEANER_SPARKLE_ACCOUNT=SuperCleaner-Production`。
- [ ] 使用 `generate_keys -x` 导出加密离线备份；导出文件等同私钥，不得提交或上传。
- [ ] 在隔离钥匙串或另一台受控机器使用 `generate_keys -f` 演练恢复，并确认公钥完全相同。

验收：Keychain account 能被 `generate_appcast --account SuperCleaner-Production` 使用，恢复后的公钥保持一致。

## 4. 一次性规则更新密钥准备

- [ ] 为规则更新生成独立 Ed25519 密钥，不复用 Sparkle 私钥。
- [ ] 私钥只存在于受控 Keychain/秘密管理系统；公开配置只放 32 字节公钥的 base64。
- [ ] 使用正式规则发布工具生成：
  - 原始 `RulePack` JSON；
  - 对原始 `packData` 字节的 64 字节 Ed25519 签名；
  - 包含 `packData` 与 `signature` 的 `SignedRuleUpdate` JSON envelope。
- [ ] 使用应用同一验证实现回读验签，再允许上传。
- [ ] 记录规则版本、`issuedAt`、累计 `revokedRuleIDs` 和发布摘要。

验收：正式公钥能通过 `CoreContractChecks --check-updates` 所使用的同类验证路径；坏签名、旧包重放和内容修改均被拒绝。

## 5. 选择托管方式

### 方案 A：官网、对象存储或静态 HTTPS 目录（当前脚本直接支持）

- [ ] 使用一个长期稳定目录，例如：

  ```text
  https://updates.example.com/supercleaner/appcast.xml
  https://updates.example.com/supercleaner/SuperCleaner-100.dmg
  https://updates.example.com/supercleaner/rules.json
  ```

- [ ] TLS 证书有效，匿名 GET 可访问，不使用 query token、Cookie 或认证 header。
- [ ] 服务器/CDN 不改写 XML/JSON、不重新制作 DMG、不注入 HTML。
- [ ] 支持先上传不可变 DMG/规则文件，最后原子替换 `appcast.xml`。

### 方案 B：GitHub Releases

当前 `publish-release.sh` 使用 appcast 所在目录作为 DMG 的下载 URL 前缀，适合“稳定 appcast 与 DMG 同目录”。GitHub Releases 通常采用稳定 appcast 地址和按 tag 变化的资产地址，因此在发布前必须先完成：

- [ ] 为脚本增加独立、显式的 archive download URL prefix；不能从 appcast URL 隐式推导。
- [ ] appcast 保持稳定 URL，例如 GitHub Pages 或官网；DMG 可以放 GitHub Release assets。
- [ ] 将 appcast、DMG、规则源及全部合法重定向涉及的实际主机加入并验证 `allowedHosts`。
- [ ] 用 staging 仓库验证 GitHub 重定向、Content-Length、原始字节和 Sparkle 下载。

未完成这些适配前，不选择 GitHub Releases 作为生产更新源。GitHub 仍可只用于源码或人工下载镜像，但不能冒充已经验收的 Sparkle 源。

## 6. 创建公开发布配置

- [ ] 从 `Resources/release-configuration.example.json` 复制到仓库外的受控绝对路径。
- [ ] 填写：
  - `bundleIdentifier`：正式反向域名标识符；
  - `teamIdentifier`：证书对应的 10 位 Team ID；
  - `ruleUpdateURL`：正式 HTTPS 规则 envelope；
  - `applicationUpdateURL`：稳定 HTTPS appcast；
  - `rulePublicKey`：规则公钥 base64；
  - `applicationPublicKey`：Sparkle 公钥 base64；
  - `allowedHosts`：所有允许的实际主机。
- [ ] 不加入私钥、密码、token、Cookie、header 或未知字段。
- [ ] URL 不包含用户信息、query token 或非默认端口。

验收：

```bash
swift run -c release CoreContractChecks \
  --validate-release-config "/absolute/path/release-configuration.json" \
  --complete
```

预期输出：`PASS: public release configuration identity, sources and signing keys`。

## 7. 每次候选版本：设置发布参数

以下值必须来自真实发布记录，尤其不能猜测上次构建号：

```bash
export SUPERCLEANER_RELEASE_CONFIG="/absolute/path/release-configuration.json"
export SUPERCLEANER_SIGN_IDENTITY="DEVELOPER_ID_CERT_SHA1"
export SUPERCLEANER_REQUIRE_STABLE_SIGNING=1
export SUPERCLEANER_VERSION="1.0.0"
export SUPERCLEANER_BUILD_NUMBER="100"
export SUPERCLEANER_PREVIOUS_BUILD_NUMBER="99"  # 首次正式发布为 0
export SUPERCLEANER_NOTARY_PROFILE="SuperCleaner-Notary"
export SUPERCLEANER_SPARKLE_ACCOUNT="SuperCleaner-Production"
```

- [ ] `SUPERCLEANER_BUILD_NUMBER` 严格大于上一个正式发布构建号。
- [ ] 未同时轮换 Developer ID 证书和 Sparkle Ed25519 密钥。
- [ ] 当前 shell 不包含明文密码或私钥。

## 8. 正式签名构建与本地预检

```bash
git diff --check
./Scripts/build-app.sh
./Scripts/verify-app.sh
./Scripts/publish-release.sh --preflight
```

- [ ] 全部核心契约通过。
- [ ] App、Helper、CLI 和 Sparkle 嵌套代码均为同团队 Developer ID 签名。
- [ ] Hardened Runtime 与安全时间戳存在。
- [ ] 不包含 `get-task-allow`、disable-library-validation 或其他弱化 entitlement。
- [ ] 嵌入的发布配置与环境指定文件逐字节一致。
- [ ] App 中的 `SUFeedURL` 与 `SUPublicEDKey` 正确。

人工复核：

```bash
codesign --verify --deep --strict --all-architectures build/SuperCleaner.app
codesign -dv --verbose=4 build/SuperCleaner.app
codesign -d --entitlements :- build/SuperCleaner.app
lipo -archs build/SuperCleaner.app/Contents/MacOS/CleanerApp
```

## 9. 公证并生成候选发布物

此步骤会访问 Apple 公证服务和 Sparkle Keychain 私钥：

```bash
./Scripts/publish-release.sh --publish
```

- [ ] `notary-result.json` 状态为 `Accepted`。
- [ ] 从结果中取得 submission ID，并且即使 Accepted 也拉取、审阅完整日志：

  ```bash
  xcrun notarytool log "SUBMISSION_ID" \
    --keychain-profile "$SUPERCLEANER_NOTARY_PROFILE" \
    "build/releases/<version>-<build>/notary-log.json"
  ```

- [ ] 公证日志没有未理解的 warning/error。
- [ ] DMG 使用同一 Developer ID Application 身份签名，已公证并 staple；DMG 内 App 的签名仍通过严格验证。
- [ ] `LOCAL-GATES-PASSED` 存在。
- [ ] `public/` 只包含准备公开的 DMG 和 appcast；不包含日志、私钥或未分发 App。

最终本机检查：

```bash
codesign --verify --strict --verbose=4 "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
xcrun stapler validate "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
syspolicy_check distribution "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"  # macOS 14+
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
```

## 10. Staging 上传顺序

- [ ] 上传候选 DMG，保持文件名和原始字节不变。
- [ ] 上传签名规则 envelope。
- [ ] 从公网重新下载 DMG/规则文件，比较长度与 SHA-256。
- [ ] 最后上传或原子切换 staging appcast。
- [ ] 不覆盖旧 DMG；旧正式版本仍能获取其原始更新资产。

## 11. 干净 Mac：首次安装与 Gatekeeper

- [ ] 使用浏览器从 staging HTTPS 下载最终 DMG，不能直接拷贝本机构建目录。
- [ ] 下载文件具有 `com.apple.quarantine`：

  ```bash
  xattr -p com.apple.quarantine ~/Downloads/SuperCleaner-<build>.dmg
  ```

- [ ] 打开 DMG，确认窗口中同时存在 `SuperCleaner.app` 与 `Applications`，将 App 拖到快捷方式后弹出镜像。
- [ ] 从 `/Applications` 中的 Finder 首次启动，而不是直接从只读镜像运行。
- [ ] 没有“已损坏”、未知开发者或公证缺失提示。
- [ ] 系统展示正确开发者身份。
- [ ] 完成扫描、退出、重新启动，历史和配置正常。

## 12. 干净 Mac：Helper 阳性验收

- [ ] 设置页请求安装 Helper。
- [ ] 若显示等待批准，在 System Settings → General → Login Items 使用管理员账户批准。
- [ ] 回到 App 后状态为 enabled；XPC ping 和 5 分钟管理员会话授权成功。
- [ ] 使用专门的可重装测试 App 验证 `/Applications` → 隔离区 → `/Applications`。
- [ ] 撤销会话后特权动作被拒绝，普通扫描和历史仍可用。
- [ ] 在系统设置撤销 daemon，状态回到需批准/不可用且不静默降级。
- [ ] 重新批准、重新注册、重启系统后再次连接成功。
- [ ] 移除 Helper 后 XPC 不可连接，但隔离内容和恢复记录仍存在。

不得使用生产关键 App 做破坏性测试。

## 13. 干净 Mac：Sparkle 升级与失败恢复

- [ ] 安装最后一个真实正式版本，而不是直接安装候选版本。
- [ ] 手动检查更新，版本、build、下载大小和开发者身份正确。
- [ ] 安装前取消一次：旧版本继续可用，Helper 状态明确。
- [ ] 再次更新并完成安装：新 build 启动，配置、历史和隔离记录保留。
- [ ] 升级后按产品流程重新注册 Helper。
- [ ] 分别验证断网、DMG 404/截断、appcast 签名损坏、DMG 签名损坏：更新必须拒绝，旧版本保持可用。
- [ ] 验证最低系统版本和所有承诺支持的 CPU 架构。

## 14. 正式上线

- [ ] 把已经在 staging 验收过的同一 DMG 上传到生产地址，不重新制作镜像。
- [ ] 从生产 URL 下载并复核长度与 SHA-256。
- [ ] 发布对应规则 envelope，并回读验签。
- [ ] 最后原子切换生产 appcast。
- [ ] 从旧正式版本再做一次生产源更新检查。
- [ ] 记录版本、build、提交 ID、证书 SHA-1、Team ID、两套公钥指纹、DMG SHA-256、发布时间和回滚联系人。
- [ ] 保留旧资产和发布记录，不重放旧构建号，不用降级覆盖坏版本；修复时发布更高 build。

## 15. 发布完成定义

只有以下条件同时满足，才标记为可向普通用户发布：

- [ ] Developer ID、Hardened Runtime、时间戳、公证、staple 与 Gatekeeper 全部通过。
- [ ] 公证日志已人工审阅。
- [ ] 规则 envelope 和 Sparkle appcast/DMG 均通过正式公钥验证。
- [ ] 公网 quarantine 首次启动通过。
- [ ] Helper 批准、撤销、重批、移动、恢复和移除通过。
- [ ] 旧正式版本到候选版本的升级、取消和失败恢复通过。
- [ ] 所有支持架构和最低系统版本通过。
- [ ] 生产 DMG 已先上线，appcast 最后原子切换。
- [ ] 没有上传私钥、公证凭据、日志或未分发 App。
