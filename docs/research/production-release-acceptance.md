# macOS 生产发布与验收核对

核对日期：2026-10-15  
范围：Apple Developer ID、公证与 Gatekeeper，`SMAppService` LaunchDaemon，Sparkle 2 Ed25519/appcast，以及本仓库现有发布脚本。只使用 Apple 与 Sparkle 的官方资料；没有进行证书申请、公证提交、Helper 注册或线上发布。

## 结论

现有 `build-app.sh`、`check-production-signing.sh` 与 `publish-release.sh` 已覆盖生产发布的主要本地机械门禁：Developer ID Application 身份、内外层签名、Hardened Runtime、安全时间戳、禁止调试/弱化运行时 entitlement、`notarytool` 提交、staple、`spctl`、Sparkle 归档及签名 appcast。

它们还不能独立证明生产可发布。正式放量前必须补齐以下事项：

1. 取得并安装带私钥的 Developer ID Application 证书，固定正式 Bundle ID 与 Team ID。
2. 创建并验证 `notarytool` Keychain profile。
3. 生成、备份 Sparkle Ed25519 私钥，把对应公钥写入公开配置。
4. 建立真实 HTTPS 更新源；先发布归档，最后原子切换 appcast。
5. 检查每次公证的完整日志，即使任务状态为 `Accepted`。
6. 在另一台干净 Mac 上通过真实公网下载触发 quarantine，完成 Gatekeeper、Helper 批准/撤销、特权操作、升级与失败恢复验收。
7. 为自定义规则更新建立生产密钥和签名封装工具。仓库目前只有验证端和测试夹具，没有面向发布者的规则签名命令；这是完整 `release-configuration.json` 的实际阻断项。

## 官方要求与仓库现状

| 主题 | 官方要求 | 仓库现状 | 仍需完成 |
|---|---|---|---|
| Developer ID | 非 Mac App Store 的 `.app`、CLI、Helper 等代码使用 Developer ID Application；公证要求所有可执行代码签名、Hardened Runtime、安全时间戳，并不得带 `get-task-allow=true`。Developer ID Installer 只用于安装包 | `build-app.sh` 以内到外签 Sparkle、Helper、CLI 和 App；生产身份启用 `--options runtime --timestamp`。`check-production-signing.sh` 校验 Developer ID OID、同 Team、标识符、时间戳及危险 entitlement | 安装正式证书和私钥；固定证书 SHA-1；确认团队与 Bundle ID 的长期所有权 |
| 公证 | 使用 `notarytool`；DMG 可作为最终交付物直接提交并 staple；成功任务也应检查日志 | `publish-release.sh --publish` 创建并签名最终 DMG，要求 `Accepted`，再对同一 DMG staple/validate，不重新打包 | 脚本没有调用 `notarytool log`，必须人工补做；30 分钟超时不代表任务失败，超时后应按 submission ID 查询，不能盲目重提 |
| Gatekeeper | 公证和 staple 后仍需验证最终交付物；真实用户路径包含下载 quarantine、挂载、拖入 Applications 与首启 | 脚本运行 DMG 的 `stapler validate` 和 `spctl --assess --type open --context context:primary-signature` | macOS 14+ 增加 `syspolicy_check distribution`; `spctl` 只是较弱的命令行近似。必须从公网下载最终 DMG，在干净 Mac 首启并观察真实系统提示 |
| `SMAppService` | macOS 13+ 用 `SMAppService` 注册 bundle 内 LaunchDaemon；`register()` 受用户批准约束，`.requiresApproval` 不是 `.enabled` | plist 位于 `Contents/Library/LaunchDaemons`，`BundleProgram` 指向 bundle 内 Helper；UI 区分注册、系统批准、XPC 连接和短时管理员授权，并可打开 Login Items 设置 | 正式签名 App 必须安装在 `/Applications` 后实测批准、拒绝、撤销、重批、重新注册、重启和升级；单元/打包 self-check 不注册真实 daemon |
| Sparkle 密钥 | `generate_keys` 一次性生成 Ed25519 私钥并存入登录 Keychain，输出 `SUPublicEDKey`；私钥必须安全备份 | 配置将 `applicationPublicKey` 写入 `SUPublicEDKey`；发布脚本通过 Keychain account 调用 `generate_appcast` | 生成正式 account、导出加密离线备份、验证可恢复性；绝不能提交私钥 |
| Sparkle 发布 | Sparkle 支持 DMG 并保留镜像内 App/链接结构；`generate_appcast` 自动生成归档签名/appcast。`CFBundleVersion` 递增；HTTPS 交付 | 首次安装和更新使用同一 DMG；强制递增整数 build；禁用 delta；验证签名 feed、归档签名、URL、长度、OS 和 build | 配置实际域名/TLS/CDN；禁止 CDN 改写 XML 或重做 DMG；先上传 DMG，最后原子切换 XML；从旧正式版本完成真实升级 |
| 签名 feed | `SURequireSignedFeed` 可保护 appcast 与 release notes；同时要启用 `SUVerifyUpdateBeforeExtraction`，修改 feed 后必须重签 | 两项均固定为 `true`，失败过期时间为 0；`generate_appcast` 生成签名 feed | 线上字节一致性与缓存策略尚未验证 |
| 架构 | 更新归档必须与目标硬件兼容，appcast 可声明硬件要求 | 当前 SwiftPM 构建默认只生成当前机器架构 | 若同时支持 Intel 与 Apple silicon，需明确采用 universal 构建或分别构建、签名、公证、发布与验收 |

## 一次性准备

### 1. 固定 Apple 发布身份

1. 在 Apple Developer 账户中创建 Developer ID Application 证书。Apple 当前说明通常需要 Account Holder，每类 Developer ID 证书最多 5 张。
2. 将证书连同对应私钥安装到构建 Mac 的 Keychain。
3. 确认可用身份：

   ```bash
   security find-identity -v -p codesigning
   ```

4. 记录证书 SHA-1、10 位 Team ID 和组织拥有的正式 Bundle ID。App、Helper、CLI 必须保持同一团队，Bundle ID 之后不要随意变更。

项目只输出包含 App 的 DMG，不生成 `.pkg`，因此当前流程不需要 Developer ID Installer 证书。DMG 和其中的 App 使用 Developer ID Application 身份。

Apple 资料：[Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)、[Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Resolving common notarization issues](https://developer.apple.com/documentation/security/resolving-common-notarization-issues)。

### 2. 创建公证凭据

推荐让 `notarytool` 交互式读取 app-specific password，不把密码写入 shell 历史：

```bash
xcrun notarytool store-credentials "SuperCleaner-Notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID"

xcrun notarytool history --keychain-profile "SuperCleaner-Notary"
```

也可使用 App Store Connect API key。`SUPERCLEANER_NOTARY_PROFILE` 填 profile 名称，不是密码。

Apple 资料：[Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)、[TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool)。

### 3. 创建 Sparkle Ed25519 密钥

使用仓库固定版本附带的工具，并给组织一个稳定 account 名：

```bash
SPARKLE_BIN="$PWD/.build/release-scratch/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account "SuperCleaner-Production"
"$SPARKLE_BIN/generate_keys" --account "SuperCleaner-Production" -p
```

第二条输出的 base64 公钥填入 `applicationPublicKey`。用 `-x` 导出私钥备份时，导出文件本身就是敏感秘密；只放入加密的离线备份或秘密管理系统，不得提交到仓库或上传到更新服务器。随后应在隔离环境用 `-f` 演练恢复，并确认恢复出的公钥完全一致。

`SUPERCLEANER_SPARKLE_ACCOUNT` 填 `SuperCleaner-Production`。不要使用已弃用的 `-s` 参数把私钥放到命令行；CI 应按 Sparkle 文档从 stdin 向 `--ed-key-file -` 提供秘密。

Sparkle 资料：[Getting started / EdDSA](https://sparkle-project.org/documentation/)、[Publishing an update](https://sparkle-project.org/documentation/publishing/)、[Security and reliability](https://sparkle-project.org/documentation/security-and-reliability/)。

### 4. 补齐规则更新签名链

公开配置还强制要求 `rulePublicKey` 与 `ruleUpdateURL`。这不是 Sparkle appcast 密钥的替代字段，而是项目自己的 `SignedRuleUpdate` 协议：对 `packData` 的原始字节做 Ed25519 签名，再将数据和 64 字节签名组成 JSON envelope。

当前仓库缺少生产用的以下能力：

- 创建并安全保存独立规则 Ed25519 私钥；
- 从规则源生成精确、稳定的 `packData`；
- 签名并输出符合 `SignedRuleUpdate` 的发布文件；
- 在发布前使用嵌入公钥回读验证该文件。

在这些能力补齐前，不应拿测试私钥、手工拼接 JSON，或复用 Sparkle 私钥来填完整配置。后者在算法上可能兼容，但会扩大单个密钥泄露的影响面，并且当前没有受支持的生产工作流。

### 5. 创建公开配置与源站

从 `Resources/release-configuration.example.json` 复制到仓库外的受控路径，至少填写：

- 正式 `bundleIdentifier` 和 `teamIdentifier`；
- HTTPS `ruleUpdateURL` 与 `applicationUpdateURL`；
- 两个 32 字节 Ed25519 公钥的 base64；
- 两个 URL 所有实际主机名组成的 `allowedHosts`。

URL 不得包含用户信息、非默认端口或 query token。源站/CDN 必须保持 appcast、DMG 和规则 envelope 的原始字节，不能做 HTML 注入、XML 重写或重新制作镜像。

## 每次候选发布

下面的值必须来自正式发布记录，尤其不能猜测 `SUPERCLEANER_PREVIOUS_BUILD_NUMBER`：

```bash
export SUPERCLEANER_RELEASE_CONFIG="/absolute/path/release-configuration.json"
export SUPERCLEANER_SIGN_IDENTITY="DEVELOPER_ID_CERT_SHA1"
export SUPERCLEANER_REQUIRE_STABLE_SIGNING=1
export SUPERCLEANER_VERSION="1.0.0"
export SUPERCLEANER_BUILD_NUMBER="100"
export SUPERCLEANER_PREVIOUS_BUILD_NUMBER="99"
export SUPERCLEANER_NOTARY_PROFILE="SuperCleaner-Notary"
export SUPERCLEANER_SPARKLE_ACCOUNT="SuperCleaner-Production"

./Scripts/build-app.sh
./Scripts/verify-app.sh
./Scripts/publish-release.sh --preflight
```

人工检查以下输出后再进行有外部副作用的提交：

```bash
codesign --verify --deep --strict --all-architectures build/SuperCleaner.app
codesign -dv --verbose=4 build/SuperCleaner.app
codesign -d --entitlements :- build/SuperCleaner.app
```

确认正式标识符、Team ID、`runtime`、时间戳、架构、最低系统版本和嵌入配置都正确后，执行：

```bash
./Scripts/publish-release.sh --publish
```

脚本会产生 `build/releases/<version>-<build>/notary-result.json`。取出 submission ID，并补做脚本当前没有执行的日志检查：

```bash
xcrun notarytool log "SUBMISSION_ID" \
  --keychain-profile "$SUPERCLEANER_NOTARY_PROFILE" \
  "build/releases/<version>-<build>/notary-log.json"
```

Apple 明确建议成功也查看日志；存在 warning 时应在发布前理解并修复，而不是只依赖 `status == Accepted`。

对已签名、公证并 stapled 的候选 DMG 再执行：

```bash
codesign --verify --strict --verbose=4 "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
xcrun stapler validate "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
syspolicy_check distribution "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"  # macOS 14+
spctl --assess --type open --context context:primary-signature --verbose=4 \
  "build/releases/<version>-<build>/public/SuperCleaner-<build>.dmg"
```

`spctl` 保留作兼容检查；Apple DTS 指出它比 `syspolicy_check distribution` 不精确。两者都不能替代真实下载首启。

## 干净 Mac 阳性验收

使用与日常开发机不同的测试 Mac/VM；至少覆盖最低支持版本 macOS 13 和一个当前 macOS。不要直接复制未隔离的本机构建目录，应先把候选 `public/SuperCleaner-<build>.dmg` 上传到 staging HTTPS 地址，再从浏览器下载。

### 首次安装与 Gatekeeper

1. 确认下载文件具有 `com.apple.quarantine` 扩展属性。
2. 打开 DMG，将 App 拖到镜像中的 `Applications` 快捷方式，弹出镜像后从 `/Applications` 的 Finder 首次启动。
3. 确认没有“已损坏”、未知开发者或公证缺失提示；系统展示正确开发者身份。
4. 完成一次扫描、退出和重新启动，确认签名、资源和本地状态均正常。

### Helper

1. 在设置中选择安装 Helper。
2. 若状态为“等待系统批准”，打开 System Settings → General → Login Items，使用管理员账户批准。
3. 回到 App 刷新，必须显示 `.enabled`，然后执行“验证连接并授权本次会话”，确认 XPC ping 与管理员授权成功。
4. 使用专门准备的、无用户数据且可重新安装的测试 App 验证 `/Applications` → 隔离区 → `/Applications` 的移动与恢复；不要用生产关键 App 做破坏性试验。
5. 撤销本次会话，确认特权动作被拒绝但普通扫描和历史仍可使用。
6. 在 Login Items 中撤销 daemon，确认状态回到需批准/不可用且不会静默降级；重新批准并再次验证连接。
7. 解除注册，确认 XPC 不可连接，隔离内容和恢复记录没有被删除。

Apple 资料：[SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)、[`register()`](https://developer.apple.com/documentation/servicemanagement/smappservice/register%28%29)、[`.requiresApproval`](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval)、[What’s new in privacy, WWDC22](https://developer.apple.com/videos/play/wwdc2022/10096/)。

### Sparkle 升级与失败恢复

1. 先安装最后一个真实正式 build，而不是当前候选。
2. staging 上先放候选 DMG，再放签名 appcast；确认 URL、Content-Length、TLS、缓存和响应字节稳定。
3. 从旧版本手动检查更新，确认版本、签名和下载大小正确。
4. 在安装前取消一次，确认旧版本可继续使用且 Helper 处于明确的未注册状态。
5. 再次更新并完成安装，确认新 build 启动、配置与历史保留；按产品流程重新注册 Helper。
6. 模拟断网、DMG 404/截断、appcast 签名损坏和归档签名损坏，确认更新被拒绝且旧版本保持可用。
7. 验证完成后，生产源仍按“归档先、appcast 后”的顺序发布；不要上传 `notary-result.json`、`notary-log.json`、未分发 App 或任何密钥。

Sparkle 还规定：常规 App 更新同时依赖 Developer ID 和 Ed25519 时，一次更新最多轮换 Apple 代码签名证书或 Sparkle Ed25519 key 中的一项，不能两项一起更换。密钥轮换应单独设计和演练，不能在首次生产发布过程中临时处理。

## 当前必须关闭的缺口

1. **阻断：规则发布工具缺失。** 完整配置要求规则更新 URL/公钥，但没有生产签名与 envelope 生成命令。
2. **阻断：外部身份和基础设施未提供。** Developer ID 私钥、Notary profile、Sparkle Keychain account、正式域名/TLS 和发布记录都不能由仓库本地测试替代。
3. **高优先级：公证日志未纳入脚本门禁。** `Accepted` 之后仍可能有 warning；当前只能人工补查。
4. **高优先级：Gatekeeper 门禁仍以 `spctl` 为主。** macOS 14+ 应增加 `syspolicy_check distribution`，并保留真实 quarantine 首启验收。
5. **高优先级：生产 Helper 没有阳性证据。** self-check、契约和签名检查都没有真正注册 daemon、经过系统批准或执行 XPC 特权操作。
6. **高优先级：生产 Sparkle 没有端到端证据。** 本地互操作契约使用临时密钥且不联网，不能证明 Keychain 私钥、CDN 原始字节、旧版本升级或失败恢复。
7. **发布决策：架构范围未固定。** 当前架构构建不能自动代表 universal 或另一 CPU 架构已验收。

只有上述阻断项关闭、干净 Mac 检查表留存证据，并且最终 appcast 尚未对生产用户公开时，才可以把候选标记为可发布。
