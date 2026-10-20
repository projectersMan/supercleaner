# SuperCleaner 开发指南

## 环境与构建

- 平台：macOS 13 或更高版本。
- 语言与 UI：Swift 6、SwiftUI、AppKit。
- 包管理：Swift Package Manager；当前没有第三方包依赖。
- 推荐使用与目标 SDK 匹配的完整 Xcode。仅有 Command Line Tools 时，脚本会选择本机兼容 SDK，但 XCTest 可能不可用。

常用命令：

```bash
./Scripts/build-app.sh
./Scripts/verify-app.sh
open build/SuperCleaner.app
```

`build-app.sh` 构建核心契约、主 App 和 Helper，并组装本地 App。`verify-app.sh` 检查 Bundle、资源、Helper、最低系统版本和签名，并在系统临时目录执行真实隔离/恢复烟雾测试。

`SUPERCLEANER_BUNDLE_ID` 可设置正式主应用标识符，Helper 标识符、Mach service、LaunchDaemon 名称和 BundleProgram 从同一值生成。主 App、Helper、CLI 使用显式签名标识符与 Hardened Runtime；证书签名使用时间戳，ad-hoc 保留明确的开发身份。构建门禁验证 `--self-check`：临时 / 示例 Helper 必须退出 78，且不能启动 listener；正式身份检查不安装、注册或弹授权 UI。

Helper 通过设置页显式注册，需放在 `/Applications`，并由系统管理员批准。再通过“验证连接并授权本次会话”开启最多 5 分钟受限操作。升级后可重新注册，先异步解除旧注册再安装本版本。恢复区内容与注册无关，移除 Helper 不清除内容；会话过期时需要权限的自动清除会失败并保留内容，不自动弹管理员授权框。

### 固定签名与重复授权

`Scripts/signing-identity.sh` 只读查询本机可用证书，优先使用 Developer ID Application，其次 Apple Development；可以用 `SUPERCLEANER_SIGN_IDENTITY` 固定证书名称或 SHA-1。主 App 与 Helper 使用同一证书。没有可用证书时，普通本地构建明确提示仍使用临时 ad-hoc 签名；临时签名的授权身份随二进制变化，重新构建后可能再次弹出访问授权。

要避免无意生成临时签名版本，使用严格模式：

```bash
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/verify-app.sh
```

缺少可用证书时，严格构建在编译和替换现有 App 之前停止；显式配置的证书失效时也直接停止。安装证书后建议使用同一个证书 SHA-1 固定后续构建身份：

```bash
SUPERCLEANER_SIGN_IDENTITY='证书 SHA-1' SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
```

证书可以从 Xcode 的 Settings → Accounts → Manage Certificates 创建 Apple Development 身份，或导入已有 Apple Development / Developer ID Application 签名身份（必须包含私钥）。脚本不会生成证书、修改钥匙串信任或修改系统隐私数据库。首次从临时签名切换到固定证书后，退出 App，在系统设置 → 隐私与安全性 → 完全磁盘访问中重新添加当前 App，然后重启；App 管理权限在实际卸载需要时由系统确认。应持续使用同一证书和 Bundle ID，以保持授权身份兼容。

依据：[Apple 代码签名身份与隐私授权](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Xcode 管理签名证书](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html)。

### 卸载分析的局部失败

应用本体身份可验证时，大小统计中的单个文件错误只产生带路径和原因的 `ScanLimitation`，不丢弃整个卸载计划。无法完整检查的关联项保持 `blocked`；用户数据和共享目录不递归读取，仅展示为“未统计”。本体大小不完整时标记估计值；本体身份无法验证时仍拒绝生成计划。`LocalFileSystem.identity` 读取链接自身元数据，不使用会跟随链接目标的存在性检查，避免 Electron `SingletonCookie` 等失效链接导致整个分析失败。

仅对指定应用执行真实只读复现（按应用已退出的条件构建计划，不执行卸载）：

```bash
swift run CoreContractChecks --check-installed-uninstall '/Applications/Example.app'
```

## 开发原则

1. 扫描必须只读，递归扫描必须限制深度、条目预算并响应取消；若为 Skill 目录建立索引，只能受限读取 `SKILL.md` 头部内容；MCP 摘要只能保留服务器名称、传输类型和项目归属，禁止把命令参数、env、headers、token、secret、源码、凭证或普通知识内容带入展示模型。
2. UI 选择与列表焦点分离；受保护项目不得通过 UI 或状态恢复进入计划。
3. 所有写入只能来自不可变 `CleanupPlan` 的真实执行。
4. 确认界面不产生文件系统副作用；`CleanupExecutor` 必须在写入前重新检查计划时效、规则版本、路径、活跃状态和文件身份。
5. 删除优先进入 App 自有隔离区；恢复不得覆盖已有路径。
6. 执行、恢复和彻底删除的意图日志必须先于文件副作用持久化；历史和调度完成后才能移除日志。
7. 同一 `planID` 只能由协调器执行一次；重复计划必须在写日志和文件副作用前失败。
8. 同一 receipt 的待执行日志复验、恢复、彻底删除、自动维护和重新调度必须共享生命周期互斥；复验获得互斥后及历史提交前必须读取最新回执，复验不得覆盖已有保留策略与重试元数据。
9. purge 日志记录准备时源存在后，恢复时源缺失应收敛为已彻底删除；准备时已缺失则保持未验证失败。
10. resolution 结果未全部进入对应终态时必须保留 journal，不得错误清除恢复依据。
11. 自动清理成功状态必须按标准化路径而非单个 UUID 清除跨模块别名。
12. 新增规则必须更新 [`docs/rule-sources.md`](rule-sources.md)，包含来源、独立验证、测试夹具和责任人。
13. 扫描态不得启动清理、应用卸载或失败项重试；UI 禁用必须由模型执行入口的同等硬门禁兜底，模块扫描控制契约必须覆盖四个扫描维度。维度底栏必须优先展示扫描状态；应用卸载与普通候选执行期间均需提供进度、停止后续项目入口并禁用重复确认删除。

## 执行生命周期开发要求

`CleanupExecutionCoordinator` 是执行事务边界：

```text
写入 execution-journal.json
  → CleanupExecutor 真实复验并隔离
  → 写入 history.json
  → 写入 quarantine-schedules.json
  → 删除执行日志

写入 resolution-journal.json（恢复/彻底删除）
  → 按日志中的稳定源/目标执行或启动复验
  → 更新 history.json
  → 协调 quarantine-schedules.json
  → 仅在全部项目进入对应终态后删除 resolution 日志
```

修改此链路时至少验证：

- 日志写入失败时没有文件移动；
- 执行中断后能按源路径/隔离路径真实状态恢复；
- 同一 `planID` 重复提交时在文件系统副作用前失败；
- 恢复/彻底删除日志写入失败时没有文件移动或永久删除；
- 恢复/彻底删除在文件副作用后写历史失败时能由启动恢复完成；
- 历史已成功而调度失败时，不会重复移动文件；
- 恢复与彻底删除只能访问回执拥有的隔离路径；
- 同一 receipt 的恢复、彻底删除、自动维护和重新调度不会并发修改，等待者基于最新历史决定后续动作；
- purge 准备时源存在且恢复时缺失，应提交 `permanentlyDeleted`；准备时源已缺失则保持失败；
- 任一恢复/彻底删除结果未解决时保留 resolution journal；
- 自动清理成功后按标准化路径清除跨模块选择、默认队列和旧失败状态；
- 原子提交失败不会破坏上一版历史或调度。

审计修复的定向回归入口为 `CoreContractChecks --check-review-recovery`、`--check-ownership`、`--check-review-coverage` 与 `--check-review-expiry`，默认全量契约同样执行它们。使用受限临时目录、内存文件系统和可控时钟，覆盖后台复验与恢复/清除/调度交错、管理来源变化后的旧关联项、Agent 深度与读取限制传播，以及五个异步边界过期；不注册 Helper、不访问真实用户清理目标。打包 CLI 另验证深度截断的真实 JSON 输出与只读行为。

## 自动删除失败与重试

到期隔离项由 `QuarantineMaintenanceCoordinator.processDue` 处理。单项未成功彻底删除时：

- 内容继续留在隔离区，历史仍保持可恢复状态；
- 调度记录写入 `AutomaticCleanupFailureReason`，包含错误码、消息和失败数量；
- `lastAttemptAt` 记录最近尝试时间；
- 历史提交前先持久化本次尝试；历史写入失败时保留 `historyPersistenceFailed` 结构化原因；
- `dueSchedules` 默认至少间隔 1 小时才再次返回该失败调度；
- App 运行时每 60 秒轮询到期项，关闭期间不运行后台常驻服务，重启后补偿。

变更重试策略时，应同时覆盖成功、部分失败、全部失败、缺失历史、已无隔离内容和重启补偿场景。

## 当前集成限制

### 公开发布配置与规则协议

`Resources/release-configuration.example.json` 是故意不可发布的模板。只填写正式 Bundle ID、Team ID、公开 Ed25519 公钥及 HTTPS 源；不得加入私钥、密码、公证凭据、Cookie、header 或带 token 的 feed query，未知字段会被拒绝。通过 `SUPERCLEANER_RELEASE_CONFIG=/绝对路径/public-config.json` 显式传给构建脚本；未设置时不会嵌入示例或启用网络更新。配置中的 Bundle ID 派生 App / Helper / CLI，若环境另设不同 ID 则构建失败。此配置校验不是证书、公证或线上发布验收。

规则更新接口为 camelCase 的 `SignedRuleUpdate` JSON：`packData` 是原始 RulePack JSON 字节的 base64，`signature` 是对这些精确字节进行 Ed25519 签名后的 64 字节 base64。RulePack 的日期沿用 Swift JSONEncoder 的 2001-01-01 UTC 参考秒数；不得把只读 CLI 的 ISO 8601 / snake_case 输出混作签名输入。`activationID` 属于本地状态，发布包必须省略；签名不是对 executionVersion 字符串计算。

发布包 `issuedAt` 必须高于已见最高包和当前随包基线，并且不能超过本机时钟 10 分钟；重复的当前原始包可作无变化检查，显式回滚后的最高包重放也会拒绝。建议发布者持续携带累计 revokedRuleIDs，接收端保存并复验历史签名证据；证明数量上限 64、单包 1 MiB、网络 envelope 1.5 MB、状态 8 MiB，超过限制拒绝更新而非丢弃撤销。新版 App 随包撤销也会与已安装包合并。HTTP 源应返回完整原始内容并尊重 `Accept-Encoding: identity`。

`CoreContractChecks --check-updates` 覆盖真实 URLSession delegate 的代送 HTTP 响应、重定向、大小/时间/取消限制及完整签名规则流程。打包门禁额外在临时 Fixture.app 中验证 CLI 从同一公开配置读取已安装规则，且不创建历史或改写状态。它们不证明实际发布主机的 TLS、证书或可用性，用户源仍待配置验证。

- 卸载图契约覆盖不同名称副本、签名应用组、独立 Label 的显式服务引用、二进制 plist、配置去敏、Homebrew/Steam 交回原渠道、真实临时 BOM 和旧计划复验。`CoreContractChecks --check-ownership` 可单独运行。系统关联文件始终保护；挂载卷应用只参与归属，不可直接删除。

- Helper：安装/异步移除、系统批准、双向签名 XPC、显式管理员会话和受限应用文件操作已接入主 App。`CoreContractChecks --check-helper` 验证无链接路径、UID/plan/身份、授权、移动恢复清除、预算、执行路由与迟到完成恢复；打包 self-check 仅检查身份，不注册或调用特权操作。真实安装/授权/连接仍须正式配置及干净 Mac；ad-hoc / 示例身份必须拒绝启动。
- 规则：签名网络分发、离线导入和回滚已接入设置页，生产扫描及 CLI 共用当前包和发布公钥。执行身份含结构化摘要与激活 ID，必须随计划传递并在执行前重新加载。撤销与 high-water 不能随回滚丢失；禁止恢复固定 `bundled-1` 的生产路径。
- 发布：脚本优先使用可用证书；缺少证书时本地构建仍是 ad-hoc 签名。严格签名验证通过也不能证明公证、staple 或 Gatekeeper 发布链完成。

### 应用更新与发布脚本

应用 feed 使用 Sparkle 2.10.0 的签名 appcast XML，不再发布旧 JSON manifest。`applicationPublicKey` 是 Sparkle Ed25519 公钥的原始 32 字节 base64；构建将 URL / 公钥写入 SUFeedURL / SUPublicEDKey，公开配置与 Info.plist 必须一致。依赖版本、源码 revision 与二进制 checksum 固定；App 中保留 Sparkle LICENSE。无需把 Sparkle 的私钥放进配置或仓库。

运行更新是显式用户行为。检查前解除 Helper 注册；取消、下载/安装失败或升级后，都需按需在设置中重新启用。准备期间扫描/清理/恢复被锁定，普通退出被阻止；最后确认立即安装后才允许退出。SDK 承担文件替换及旧版本恢复，实际特权安装、崩溃/断电行为尚须干净机验证；这不是启动后健康探测或自动降级系统。修复有问题的正式版本应发布更高构建号，不能重放旧构建。

发布环境需显式提供以下变量（均为路径、公开身份或 Keychain 中的名称，不是密码/私钥）：

- `SUPERCLEANER_RELEASE_CONFIG`：完整公开 JSON 的绝对路径。
- `SUPERCLEANER_SIGN_IDENTITY`：Developer ID Application 证书名称或 SHA-1。
- `SUPERCLEANER_VERSION`、`SUPERCLEANER_BUILD_NUMBER`：展示版本 x.y.z 与递增正整数构建号。
- `SUPERCLEANER_PREVIOUS_BUILD_NUMBER`：上次正式构建号；首次发布为 0。必须从真实发布记录取得，门禁不能证明这个人工输入正确。
- `SUPERCLEANER_NOTARY_PROFILE`、`SUPERCLEANER_SPARKLE_ACCOUNT`：已有公证 Profile / Sparkle Ed25519 Keychain account；脚本不创建或导出私钥。

先构建、验证，再运行 `./Scripts/publish-release.sh --preflight`。它是只读本地检查，严格拒绝开发 / ad-hoc 签名、错团队、缺少 Runtime/时间戳和不安全 entitlements；不验证私钥或公证凭据的可用性。本地 ad-hoc 构建为加载无 Team ID 框架而不启用 Runtime，不添加禁用 library validation 的 entitlement，且绝不能越过正式发布门禁。

只有显式 `./Scripts/publish-release.sh --publish` 才创建新 `build/releases/<version>-<build>/`。脚本复制已签名 App，调用 `create-dmg.sh` 生成包含 App 与 `/Applications` 快捷方式的只读 DMG，使用同一个 Developer ID Application 身份签名 DMG，再提交 notarytool 并检查 Accepted、staple/validate 和 Gatekeeper，最后用该 DMG 生成签名 appcast。公开公钥门禁再次检查 feed/归档签名、build、OS、主机和长度。任一步失败保留 staging 供排查，不产生 `LOCAL-GATES-PASSED`，不覆盖旧发布、不自动重试。成功也仅表示本地发布门禁通过：完成干净机验收后，人工上传 `public/` 内 DMG，最后原子切换签名 XML。不要上传 notary 日志、staging app 或密钥。

更新 DMG / appcast 必须保持原始字节，不允许 CDN 改写 XML、HTML 压缩或重新制作镜像。发布源为 HTTPS；当前配置和自动生成 feed 都不使用带 token 的 URL。应用传输由 SDK 管理，逐跳主机和网络预算策略不能直接套用规则更新的测试结论。SDK 的 Ed25519 信任链允许证书轮换；同团队和公证检查位于本项目发行门禁，不能误写成 SDK 强制每次同团队/公证。默认仅构建当前架构，其他架构必须分别构建/验收，appcast 会标明硬件要求。

构建门禁使用随机临时测试密钥证明 Sparkle 官方 sign_update 与本项目公钥验证器互通、篡改拒绝；测试不会读取用户 Keychain。打包 App 的 `--update-self-check` 验证实际框架加载、最终确认/取消和退出保护，不启动更新器、不联网、不注册 Helper。它们不是已完成真实升级的证据。

依据：[Sparkle 发布指南](https://sparkle-project.org/documentation/publishing/)、[安全与自动更新设置](https://sparkle-project.org/documentation/customization/)、[固定 2.10.0 源码](https://github.com/sparkle-project/Sparkle/tree/2.10.0)。升级 SDK 版本必须重新核查签名 feed、准备/恢复安装和取消语义，并运行本项目的打包门禁，不能只改版本号。

## 验证顺序

面向官网、GitHub 或其他 HTTPS 渠道的站外正式发布，使用 [`production-release-checklist.md`](production-release-checklist.md) 逐项验收；该流程不涉及 Mac App Store，但要求 Developer ID Application、公证、Sparkle 签名和真实公网下载测试。

1. 运行 `git diff --check`，排除空白和补丁格式问题。
2. 运行 `./Scripts/build-app.sh`。
3. 运行 `./Scripts/verify-app.sh`。
4. 在完整 Xcode 环境运行 `swift test`。
5. 审查 `git diff --name-only`，确认改动范围符合任务约束。
6. 发布前使用正式 Bundle ID、Developer ID 和 Hardened Runtime 归档，完成公证与 staple，并在干净 Mac 验证 Gatekeeper、升级、Helper 安装/移除及权限降级。

## 文档维护

- [`README.md`](../README.md)：面向使用者，说明能力、数据流程、运行命令和发布边界。
- [`docs/architecture.md`](architecture.md)：记录模块责任、运行时数据流和当前接线状态。
- 本文件：记录开发约束、验证方法与发布门禁。
- `docs/superpowers/` 与 `docs/verification/`：保留历史设计和阶段证据；实现变化后必须添加现态说明，不能把历史结论继续描述为当前能力。
- Agent 环境若调整 Skill 主视图、目录辅助视图或逐条删除决策能力，必须同步更新 README、Dashboard 文案和架构文档中的“只读边界”“逐条显式选择”与“默认不自动清理”表述，避免把 manifest 头部解析误写成“完全不读文档内容”，也避免把 Agent 环境误导成默认清理模块。
- Agent 一级目录分组不再维护外部注册表，必须统一通过 `AgentCatalogRegistry.swift` 中的推断逻辑演进；新增推断规则时优先增强“固定根目录 + 真实文件夹 + Skill Markdown 标记”的识别顺序，不要把规则散落到多个页面文件中。
- Codex、Claude 等供应商的 Skill/MCP 文件系统位置必须统一维护在 `AgentResourcePathRegistry.swift`；MCP 格式识别与去敏解析统一维护在 `MCPConfigurationCatalog.swift`。更新规则时同步修改官方来源研究记录和 Agent scanner contract，禁止在 View 或 Adapter 中重新散落路径字面量。
- 修改大文件或 Agent 扫描时，必须同时检查 Spotlight 快速路径、精确递归回退路径和生产预算；不能在 Spotlight 已成功后无条件再次递归扫描整个 Home。
