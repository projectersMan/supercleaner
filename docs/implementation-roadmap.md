# Mole 能力补齐：实施与验收

目标：完整实现对照审计中评分 ≥80 的七项建议。评分仅表示优先级；本任务已经获得实现授权。保留独立实现，不复制 Mole 源码、规则实现或特有结构。

## 验收清单

- [x] 98：生产扫描由当前已验证 RulePack 驱动；规则包含来源、系统版本、候选粒度、活动探测、保护例外、默认选择与预算；撤销、升级、回滚对新计划和执行复验生效。
- [x] 96：持久保护清单可在界面维护；扫描、计划、执行共享策略；保护父目录/子目录交叠与符号链接目标；策略变更后旧计划不能绕过保护；读取失败时拒绝删除。
- [x] 94：卸载所有权图包含应用副本、安装来源、共享资源与服务引用；支持用户/系统关联类别与安装收据；官方卸载器/包管理安装来源有明确处理；配置引用仅报告文件和位置。
- [x] 91：项目分组产物清理包含 node_modules、target、.build、build、dist；可配置扫描根；识别 Git tracked、嵌套仓库、密钥与活动；接入明确选择、复验、隔离与恢复。
- [x] 88：版本化只读 JSON 接口覆盖扫描报告、候选证据、完整性、计划预览和历史；成功输出稳定，失败走 stderr/非零退出；没有隐式破坏性入口。
- [ ] 87：Helper、规则/应用更新及发布门禁实现和本地检查已完成；正式签名、公证、真实升级失败恢复与干净机阳性验收待外部配置，尚不能勾选整体完成。
- [x] 82：安装包多来源发现，支持 MPKG 与安装 ZIP；累计时限、条目/深度预算、坏 ZIP/不可读/取消结果处理、最终身份复验。

## 外部验收条件

真实 Developer ID 身份、正式 Bundle ID、发布更新源及签名公钥、公证凭据、干净 Mac 验证必须来自用户/发布环境。实现可提供配置和门禁，但缺少这些条件时不得宣称生产发布验证完成。

## 批次记录

开始状态：工作区干净；现有生产扫描固定使用 bundled-1；Helper、RuleStore、UpdateService 尚未接入主 App；XCTest 在当前 Command Line Tools 环境不可用，可运行独立 CoreContractChecks。

### 批次 1：规则、保护、安装包、JSON 与项目产物（2026-10-15）

实际修改：

- 新建 CleanupRuntime/CleanupRuleEngine，生产扫描改用当前规则包，版本绑定规范化内容摘要；每条规则独立失败，明确来源、活动工具、默认选择和检查预算；uv 缓存遵从官方要求禁止直接移动。
- 新建 ProtectionStore/ProtectionPolicy，设置和候选菜单维护持久清单，扫描/计划/逐项执行共享保护，文件损坏与链接替换拒绝删除。
- 新建有时限/输出限额/取消支持的进程适配器，以及多来源安装包发现和 ZIP 完整性验证。
- 新增随 App 打包的 supercleaner，只读 schema v1 JSON 与明确计划预览；专项项目命令复用项目扫描器。
- 新建独立项目产物页面、扫描根存储、项目分组、只读 Git 跟踪检查、密钥/嵌套仓库/活动保护，复用事务隔离与恢复。
- 修正旧取消契约对主测试任务的污染；增加规则、保护、安装包、JSON、项目产物及打包 CLI 契约。

验证：核心契约、原生 App/Helper/CLI 构建、Bundle/签名结构及真实临时目录隔离恢复通过；打包 CLI 独立契约列入构建门禁。XCTest 仍受当前 Command Line Tools 环境限制；正式签名、公证与干净机验证尚未完成。

下一批次必须完成：94 分卸载所有权图；87 分 Helper 与签名更新/发布链。当前不得将整体目标标为 complete。用户已回复发布配置“暂无”；不应重复询问，也不应把它当成停止代码实现的理由。先完成全部实现、配置入口和发布门禁，再将真实证书签名、公证、更新源托管和干净机验收单独标记待验证。

最终批次 1 门禁：`./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 通过；包括全部现有契约、四组新增核心契约、打包 CLI 的真实进程输出/错误/只读检查，以及隔离恢复烟雾测试。未执行真实用户数据清理，未安装或提权调用 Helper，未提交/推送代码。

### 批次 2：卸载所有权图（2026-10-15）

实际修改：

- 新建 `ApplicationOwnershipGraphBuilder`，统一应用副本、签名应用组、资源拥有者、服务与配置位置。同 Bundle ID 的不同名称副本保留共享资源，不再单应用推断独占归属。
- 扩展用户日志、WebKit/HTTP 存储与系统关联类别；受限解析服务显式路径，Label 不构成删除许可。系统资源、服务引用、共享资源与用户数据保持保护。
- 新建只读安装来源检查：当前 Cask JSON、Steam 库与 manifest、App Store 收据线索、安装收据+BOM 精确载荷关联。包管理器 / 官方工具 / 服务管理应用交回原渠道，不直接移动本体或关联文件、不执行 zap 或未知脚本。
- 应用页及 JSON 展示图、来源、收据和引用位置。官方 app-bundle 卸载器需同签名团队、显式确认及启动前完整签名复验，其修改不包含在本应用恢复保证内。
- 新建逐项执行归属复验，新增副本、服务、管理来源或活动状态会拒绝旧计划；本体先隔离后仍用原标识符验证关联项。有限应用发现包含本地挂载卷及 Steam 库；挂载卷应用只参与归属，不提供直接删除。
- 内容读取改为普通文件、大小限额和前后身份检查；图预算耗尽或引用不可验证时不授予关联项删除权限。配置引用模型仅有文件、行号、种类，无命中内容、参数或秘密。

验证结果：

- 新增所有权契约通过：不同名称副本、应用组多拥有者、独立 Label 服务、二进制 plist、配置位置与去敏、预览后新增副本/服务拒绝、移除副本后恢复资格、Cask/Steam 原渠道处理、真实临时 BOM、预算与链接配置拒绝。
- `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 在本批最终源代码上通过，包括全部既有契约、App/Helper/CLI 生产构建、打包 CLI JSON/错误/只读检查、签名结构和临时目录隔离恢复。
- 仍使用 ad-hoc 本地签名；XCTest 仍受 Command Line Tools 环境限制。未清理真实用户数据，未运行包管理卸载命令或官方卸载器，未安装或提权调用 Helper，未提交/推送。

目前完成 6/7 项；87 分 Helper 与签名更新/发布链仍待实现。整体目标保持未完成，继续下一批。正式 Bundle ID、证书、公钥、更新源与公证配置暂无；它们仅限制真实生产验收，不作为停止代码实现的理由。

### 批次 3：Helper 接线与不确定结果恢复（2026-10-15）

实际修改：

- 新建 `HelperSigningIdentity`、`HelperAuthorizationSession`、`XPCPrivilegedHelperClient`、`HelperServiceManager`、`AuthorizedApplicationOperations` 和 `HelperFileOperations/HelperRequestHandler`。设置页明确区分注册、系统批准、连接验证与 5 分钟会话授权；支持异步移除和升级后重新注册。
- 两端使用公开的按消息 code-signing requirement，绑定精确标识符、Apple 证书链、Team ID 和非调试身份；删除 PID-only 验证。Home 从连接有效 UID 的系统账户派生，不能由请求指定；每次修改独立检查管理员授权、短期 token、摘要、nonce、planID、UID 和身份。
- 应用隔离、恢复和清除通过统一受限接口进入执行器；没有授权不发送 Helper 请求，权限错误不自动提权或重试。根操作采用 fd-relative / O_NOFOLLOW / 非覆盖 renameatx_np / unlinkat，拒绝跨用户、链接祖先、挂载点、网络卷、路径跳转和目标冲突，不提供任意系统删除或服务脚本接口。
- 取消已发送修改只停止后续项目；连接丢失、超时等不确定结果保留日志和确定的隔离路径。请求过期及宽限后按身份复验，迟到完成更新原恢复记录；活动计划不进入恢复重放。移动和恢复增加身份后验。
- 打包改为 SMAppService 的 LaunchDaemons + BundleProgram 布局，移除旧 SMJobBless 元数据；同一可配置 Bundle ID 派生主 App / Helper / CLI 标识符，启用 Hardened Runtime，正式证书使用时间戳。Helper self-check 不注册或启动 listener，临时 / 示例签名必须拒绝。

验证结果：

- Helper 安全契约通过：真实 Security requirement 编译、无授权拒绝、UID/plan/身份/路径校验、链接祖先拒绝、真实临时目录的移动恢复及不跟随链接清除、预算和超大请求拒绝。
- 执行契约通过：授权接口只调用一次、恢复身份后验、无本地重试、不确定结果保留日志、等待在途窗口、迟到完成补入原回执。原生 XPC 的不存在服务和取消 ping 走有界失败路径；未以此声称真实签名 Helper 连接已验证。
- 最终 `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 通过：全部核心契约、App/Helper/CLI 生产构建、打包 CLI、Helper 身份负向门禁、签名结构和临时目录隔离恢复。
- 未安装 / 注册真实 Helper，未触发管理员授权，未对真实用户应用执行提权操作，未提交/推送。仍是 ad-hoc 本地构建；正式签名 / 公证 / 干净机特权验收尚未完成。

87 分条目仍未完成，下一批必须完成：

- [x] Helper 安装/移除、认证客户端、受限文件操作与主 App 接线（本地验证完成，真实发布验证待配置）。
- [x] 签名规则网络更新、导入与回滚界面；更新下载的协议/来源/大小/重定向/取消限制及失败保持当前包。
- [x] 应用签名 appcast/DMG、明确批准安装、拒绝降级；官网首次安装与 Sparkle 更新共用拖放式 DMG，固定 Sparkle 承担下载/归档验证/替换及安装失败恢复。发行门禁检查同团队 Developer ID 与公证，不冒充 SDK 运行时强制每次同团队/公证；真实安装失败仍待外部阳性验收。
- [x] 正式配置入口、签名/公证/staple/发布检查；本地更新策略、篡改拒绝、最终确认/取消、SDK 签名互通及 ad-hoc 拒绝测试门禁。
- [ ] 使用用户正式配置在干净 Mac 验证真实 Helper、Gatekeeper、公证、升级及权限降级。

整体仍是 6/7 项完成，继续更新与发布链工作。不得以缺少证书停止可独立完成的代码与门禁，也不得把本地阴性验证替代生产阳性验收。

### 批次 4：签名规则更新、共享配置与网络限制（2026-10-15）

实际修改：

- 新建公开 `ReleaseConfiguration`，GUI 与打包 CLI 共同加载；严格拒绝未知 / 私钥字段、非明确主机、无效公钥格式和带凭据的 feed。默认配置缺失时禁用更新，不嵌入示例。构建增加显式配置入口、身份派生和配置预检。
- 新建流式 HTTPS 下载模块及 `RuleUpdateService`，接通网络更新、离线签名导入、取消及确认回滚；源、每次重定向、响应、累计字节与时限均受限，不发送 Cookie / 凭据，不覆盖已有输出，失败保留当前包。
- `RuleStore` 改为单个原子 state，保存当前/上一份包、签名 high-water 和撤销证明；首次失败保留等价 baseline，旧格式只读兼容后显式迁移。回滚不降低 high-water、不丢撤销；新 App 随包撤销也对已安装包生效。持久 activationID 和结构化内容摘要使每次激活 / 回滚废弃旧计划，重复当前包不清空选择。
- 当前签名损坏时可显式切回仍可信上一份；损坏上一份不展示为可用目标。新旧包、证明和状态都有容量约束，状态丢失 / 链接替换不回落到旧规则。
- 设置页与扫描、清理、恢复、Helper 修改、后台维护互斥；激活后清空旧扫描、候选选择和项目确认。修正随包规则误写到 10 月 17 日的发布时间为实际验证日 10 月 15 日。同步规则测试与旧 XCTest 存储路径 / 异步取值。

验证结果：

- 原生 URLSession delegate（URLProtocol 代送响应）验证流式 SHA256、独占文件、无凭据、合法跳转、拒绝越域/降级跳转、循环预算、响应 / 大小 / 截断、取消与时限，未连接真实用户发布源。
- 签名规则流程验证坏签名 / 网络失败 / 取消保留当前、原子故障与首次 marker 后失败、签名撤销保留、版本重放拒绝、激活稳定性及失效、可信回滚修复、不可用上一份、旧格式迁移、状态丢失与根链接拒绝、随包撤销覆盖已安装包。
- 最终 `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 通过。新增打包 CLI 真实进程契约证明其使用公开配置的同一公钥和已安装签名规则，并保持只读；全部既有契约、App/Helper/CLI 构建、签名结构及隔离恢复通过。
- 示例公开配置 `--complete` 预检按预期失败（退出 1），没有把占位值当正式配置。XCTest 仍受 Command Line Tools 环境限制；未更新真实用户规则、未安装 / 提权 Helper、未提交 / 推送。

87 分条目尚余：完整应用更新流程（签名、下载、验证、批准安装、失败恢复与降级拒绝）；正式签名、公证、staple 及发布门禁；用户真实配置下的干净机验收。总体仍为 6/7，继续下一批，不得标为 complete。

### 批次 5：应用更新、发布门禁与最终归属审计（2026-10-15）

实际修改：

- 将未接线的 JSON `UpdateService` 替换为生产 `ApplicationUpdatePolicy`，固定 Sparkle 2.10.0 及 revision/checksum，打包框架、嵌套代码签名及许可证。版本区分展示版本与递增 CFBundleVersion；正式配置不完整 / 身份不符时不初始化网络更新。
- 接入手动检查与安装；签名 feed 必须验证且永不超时放行，归档解包前校验，拒绝降级、包安装器及增量。禁用自动检查/下载、画像、远程 release notes 和 JavaScript。更新与清理/恢复互斥，先解除 Helper 注册；最后确认立即安装或取消，不提供延期退出安装。准备阶段阻止普通退出，恢复旧更新的路径也重新验证当前策略。
- 以 `codebase-design` 收拢更新接口：SDK 承担真实安装，不新增自制提权安装器。明确 SDK 的 Ed25519 证书轮换语义、传输与 Gatekeeper 预热边界，不能把规则传输预算或发行门禁误写成应用运行时保证。
- 新建只读正式签名门禁及显式发布脚本：要求完整公开配置、确切 Team / 标识符 / Developer ID、Runtime / 时间戳与安全 entitlements；`--publish` 才访问签名 Keychain、创建并签名拖放式 DMG、提交公证。Accepted、DMG staple/validate、Gatekeeper、签名 DMG/appcast 公钥复验全部通过才写 `LOCAL-GATES-PASSED`。不覆盖旧 staging、不上传，仍需干净机验收。
- 新建 `SignedApplicationRelease` 离线公钥门禁，检查签名 XML / DMG、版本/OS/主机/长度与 SHA256，拒绝篡改、歧义 metadata、DTD 与链接归档；首发 build 1 可发布，客户端仍拒绝同版本。
- 最终 94 分审计补上应用包内 LoginItems、LaunchAgents/Daemons、LaunchServices；存在定义只表示潜在服务，不宣称已注册。交回原渠道，归属检查受限时预览与执行都不再允许应用本体直接卸载。
- 依 `diagnosing-bugs` 的打包失败回归信号定位 ad-hoc 无 Team ID 与 Hardened Library Validation 冲突：仅开发签名不启用 Runtime，正式发行仍强制 Runtime；未添加禁用 library validation 的 entitlement。目录 URL 尾斜杠差异仅修正测试比较，保留真实服务保护。

验证结果：

- 最终代码上 `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 通过；全部规则、保护、安装包、只读接口、项目、所有权、Helper、恢复和签名规则更新契约继续通过。
- 新增策略验证：严格递增 / 拒绝降级与坏构建号、主机/协议/凭据/端口、归档类型/声明长度、签名 feed 和手动更新设置；签名 XML/DMG 篡改、metadata、DTD 与链接拒绝通过。
- 固定 SDK 官方 `sign_update` 与 CryptoKit / 公开发布门禁的双向签名互通通过；随机临时测试密钥，不读取用户 Keychain。打包 App 实际加载 Sparkle 并验证最后确认/取消及退出保护，无更新器启动、网络或 Helper 操作。
- 正式门禁在完整有效公开配置下仍拒绝 ad-hoc 应用；发布 preflight 在用户配置“暂无”时按预期非零退出。脚本语法检查通过。未提交公证、未托管源、未真实升级或提权卸载；未提交/推送代码。XCTest 仍受当前 Command Line Tools 环境限制。

最终状态：七项建议的代码侧与可本地执行的门禁已实现；87 分真实生产阳性验收仍未完成，因此整体目标不能标记 complete。唯一剩余必要工作是用户/发布环境提供正式配置后，在干净 Mac 执行真实 Helper 安装/移除/权限降级、Gatekeeper、公证及升级失败/恢复验收。配置缺失已经连续记录于批次 2、3、4、5；目前不再有可独立推进的代码工作，等待外部条件，不启动新的优化任务。

### 批次 6：完整性回归、规则扩充与 GUI 深模块（2026-10-15）

实际修改：

- Agent 扫描在深度边界、目录读取失败和路径身份失败时保留模块、provider 与具体路径三层完整性证据；只读 JSON 不再把截断扫描声明为 complete。
- 随包规则升级为 `bundled-3`，从 10 条扩充到 15 条。新增 Go 构建缓存、Deno、Cargo 下载缓存、CocoaPods 和 Playwright 浏览器规则；只有官方明确可重建的 Go 构建缓存默认安全，其余保持 review。Playwright `daemon` 持久会话显式保护，Cargo 规则根仅覆盖下载缓存，不包含凭证、配置和二进制。
- 规则契约要求每条随包规则都有来源类型、稳定 source reference、测试夹具和所有权证据，并验证 reference 实际存在于来源台账；新增规则均使用官方一手文档，不复制第三方清理产品规则。
- 新建 `HelperSettingsModel`，集中 Helper 注册、系统状态、XPC 签名身份验证、5 分钟会话授权、撤销与升级前移除；设置页直接观察该模块，`AppModel` 不再转发 Helper 状态和生命周期方法。
- 新建 `AppInfrastructure` 构造 seam，隐藏文件系统、规则运行时、隔离执行器、历史/执行/恢复日志、调度和 Helper 授权适配器装配。`AppModel.swift` 从 1912 行降至 1794 行，中央模型保留产品状态与跨功能互斥。

验证结果：

- `RuleEngineContract --check-rule-engine` 通过：15 条目录规模、来源台账、精确 Go 规则优先级、签名更新/回滚和保护策略均通过。
- `ReviewRegressionContract --check-review-coverage` 通过：深度、读取、身份失败、provider evidence、空边界和只读负载全部通过。
- `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff --check` 通过：全部核心契约、Sparkle 公钥互通、App/Helper/CLI Release 构建、打包 CLI、Helper 身份负向门禁、签名结构和临时目录清理/恢复均通过。
- 正式发布 `--preflight` 已实际执行并按设计拒绝：7 个正式发布变量均缺失，本机 Developer ID Application 身份为 0。未访问私钥、未提交公证、未注册 Helper、未修改真实用户数据。

当前代码侧四项任务均完成；正式生产阳性验收仍等待发布环境提供真实身份、公开配置、公证与 Sparkle Keychain 条目，并需在干净 Mac 执行。不得以本批全绿的本地门禁替代该外部验收。

### 批次 7：批准的审计修复与过期防护回归（2026-10-15）

范围：仅落实已批准的三项审计问题与补充计划过期风险。按 `diagnosing-bugs` 与 `tdd` 固化复现，再通过公有接口验证；不自动启动新的优化任务。

实际修改：

- 后台待执行日志复验纳入同一 receipt 生命周期互斥，获得互斥后读取最新历史，避免覆盖已完成的恢复或彻底删除。复验保留用户已调整的保留策略、到期时间与重试元数据；App 空闲复验也避让手动恢复和维护。
- 应用本体与关联项执行前共用管理来源门禁；新出现 Homebrew 收据或服务管理时，旧计划的关联缓存也拒绝移动。本体缺失时的归属锚点同样受约束，所有者证据缺失按拒绝处理。
- Agent 扫描将深度/条目截断、目录枚举和身份读取失败传播至平台、模块、覆盖路径和 JSON；空深度边界不误报。完整扫描与单模块刷新保留限制，JSON 增加 `agent_provider_coverage`。
- 保留并核验工作区同期补入的计划时效检查：异步安全验证、活动检查、身份读取、隔离目录准备后及权限操作回退前均拒绝过期后的新移动；补充五个可控时钟回归，并验证不发起新的 Helper 移动请求。
- 新增 `ReviewRegressionContract` 与三个定向入口，默认全量契约包含这些回归；打包 CLI 增加真实深层目录的只读 JSON 限制验证。同步架构与开发约束，未覆盖同期其他功能改动。

验证结果：

- 恢复、彻底删除、重新调度与后台复验交错，以及已有保留策略不被重置，均通过。
- 新服务、新 Homebrew 收据、本体缺失后的旧关联项拒绝通过；Agent 深度截断、读取失败、身份失败、空边界、平台证据、完整扫描与刷新传播通过，测试负载保持不变。
- 五个过期边界均通过：原内容保持原位，结果为受保护跳过；过期前未发出的 Helper 请求数量为零，权限接口拒绝后的本地回退不再移动。
- 全量 `CoreContractChecks`、Sparkle 签名互通、App/Helper/CLI Release 构建、打包 CLI、Helper 身份与正式签名负向门禁、签名结构、隔离/恢复烟雾流程均通过；`git diff --check` 通过。为避开共享打包目录争用，最终构建与验收在独立临时快照执行；源码、脚本、资源及包配置的聚合 SHA-256 与工作区一致：`0d0ddf5438b56fcb1ca6600c3a4bcd307368f5e2da801130267738fbbc1f13a6`。
- 当前 Command Line Tools 环境的 XCTest 限制仍在，不宣称 XCTest 通过。未注册 Helper、未触发管理员授权、未清理真实用户数据、未提交公证、未发布、未提交/推送代码。

本批批准范围已完成。正式签名、公证、真实升级失败恢复及干净 Mac 阳性验收仍待外部条件，整体生产验收状态不变。

### 批次 8：单一 DMG 安装与更新交付（2026-10-15）

实际修改：

- 新增 `Scripts/create-dmg.sh`：从已签名 App 生成只读压缩镜像，根目录只提供 `SuperCleaner.app` 与 `Applications → /Applications` 快捷方式；创建后只读挂载，复验布局和镜像内 App 的完整签名，失败时清理不完整产物。
- `publish-release.sh --publish` 改为只生成 `SuperCleaner-<build>.dmg`：使用 Developer ID Application 身份签名 DMG，直接提交该 DMG 公证，对同一字节序列 staple、校验镜像和 Gatekeeper，再以同一 DMG 生成 Sparkle appcast。公开目录不再生成 ZIP。
- `ApplicationUpdatePolicy` 与离线签名发布契约只接受完整应用 DMG，明确拒绝 ZIP、PKG、增量、非允许主机、查询参数和异常声明长度；测试 fixture、篡改/链接归档测试同步切换为 `.dmg`。
- README、开发指南、架构、研究记录及站外发布清单统一为：首次安装和 Sparkle 更新共用一个 DMG；不需要 Developer ID Installer，但仍必须使用 Developer ID Application 与 Apple 公证。

验证结果：

- `zsh -n Scripts/create-dmg.sh Scripts/publish-release.sh` 与 `git diff --check` 通过。
- 实际生成、挂载并校验本地 DMG：镜像为只读 UDZO，包含有效 `SuperCleaner.app` 和指向 `/Applications` 的符号链接；`hdiutil verify` 通过。
- Sparkle 2.10.0 `generate_appcast` 使用临时测试密钥成功读取该 DMG，并从镜像内 App 推导 build 1、最低系统版本 13.0 和 `.dmg` enclosure；未访问用户 Keychain。
- `./Scripts/build-app.sh` 通过全部核心契约、DMG 更新策略、Sparkle 签名互通及 App/Helper/CLI Release 构建；`./Scripts/verify-app.sh` 通过签名结构、Sparkle 加载和隔离恢复烟雾验证。首次构建在复制 Sparkle 许可证时出现一次瞬态目标目录缺失，未修改代码即复跑通过，无法稳定复现。
- `swift test` 仍因当前 Command Line Tools 缺少 XCTest 失败；未使用正式证书、未提交公证、未上传资产，也未声称完成干净 Mac 阳性验收。

本批授权实现已完成。剩余必要工作仍是提供正式发布身份与配置后执行真实 DMG 公证，并在干净 Mac 验证公网下载、Gatekeeper 首启、Helper 和 Sparkle 从旧正式版本升级。
