# SuperCleaner 架构与当前实现

## 目标与边界

SuperCleaner 是 Swift 6 / SwiftUI 的 macOS 清理应用。核心原则是只读发现、明确选择、不可变计划、真实执行前复验、可恢复隔离和可审计历史。当前代码由 `CleanerCore`、`CleanerApp`、`CleanerHelper`、`CleanerCLI` 与 `CoreContractChecks` 五个目标组成，定义见 [`Package.swift`](../Package.swift)。

## 模块职责

- `Sources/CleanerCore/`：扫描、分类、计划、安全策略、执行、历史、隔离调度、规则存储和 Helper 协议。
- `Sources/CleanerApp/`：SwiftUI 页面与 `AppModel` 编排；将扫描结果、选择、执行进度、历史和调度状态投射到界面。
- `Sources/CleanerHelper/`：受限 XPC Helper 入口；双向按消息校验签名身份，按连接 UID 派生本用户范围，复用 Core 内的授权和无链接文件操作。
- `Sources/CoreContractChecks/`：不依赖 XCTest 运行环境的核心契约验证。
- `Tests/CleanerCoreTests/`：在完整 Xcode 环境中运行的 XCTest。
- `Sources/CleanerCore/Resources/`：GUI 与 CLI 共用的随包规则资源；来源责任记录在 [`docs/rule-sources.md`](rule-sources.md)。
- `Sources/CleanerCLI/`：只读 JSON 命令入口，调用与 GUI 相同的 `CleanupRuntime`。

## 扫描与计划

`SystemScanCoordinator` 并行运行系统清理、应用、较大文件和 Agent 环境模块，并以同一 `generationID` 汇总为 `SystemScanReport`。模块结果可渐进展示；完整重扫会产生新 generation，使旧选择与旧计划失效。页面不提供普通的单模块刷新；用户更改大文件阈值时会重扫大文件模块。Agent 环境模块同时产出 `agentAssets`、`agentSkills` 和 `agentMCPConfigurations`：分别承载环境目录与真实清理单元、Skill 元数据与分组索引、MCP 配置来源和去敏服务器摘要。

应用关联仅接受完整 Bundle ID、带明确 `.` 边界的 Bundle ID/group ID，或与应用显示名完全相等的名称。只有 Bundle ID 或 group ID 的完整边界匹配可把非活跃缓存判为 `safe`；仅显示名命中的缓存保持 `review`。裸产品名或 token 前缀不构成所有权证据，避免相似产品名称误关联。Dashboard 直接展示每个模块的真实状态和摘要，不把应用模块的 `limited` 降格显示为完成；应用维度只展示聚合 `message`、状态和清理摘要，不在 Dashboard 展开逐条限制路径，其他维度继续展示逐项限制。

`ApplicationOwnershipGraphBuilder` 对已发现的应用建立统一所有权图，不再按单个应用独立猜测可删资源。相同 Bundle ID 的不同名称副本拥有同一批关联资源；签名声明的应用组按所有声明者合并。用户日志、WebKit/HTTP 存储、启动代理及 `/Library` 系统关联类别纳入图；系统文件、共享容器、仍有服务/配置引用的资源保持保护；经完整 Bundle ID 匹配并确认独占的用户数据可由用户单独勾选，默认不选。服务只受限解析 plist 中的显式路径，不执行脚本、不凭 Label 认定可删。应用清单不完整或图预算耗尽会保留覆盖范围提示，但不会覆盖已识别资源自己的归属和风险结论；引用不可验证的具体资源仍保持保护。

应用发现包括标准应用目录、Steam 已知库以及本地挂载卷的根级应用和 Applications 目录；不遍历整盘、备份或网络卷。挂载卷应用仅作为其他副本的所有权证据，不提供删除。生产发现/图构建有明确条目、深度和时间预算；限制通过覆盖信息公开。

`LocalApplicationInstallationInspector` 只读解析当前 Homebrew Cask JSON、Steam ACF/VDF、Mac App Store 收据线索以及安装收据+BOM 中的精确载荷路径，不根据包名猜应用、不删除收据、不运行安装管理命令。未识别的旧格式保持来源未知，不能声称来源已穷尽。Homebrew/Steam 或服务管理应用不进入本应用的直接卸载；提供原渠道说明与安全格式的命令复制。只对同签名团队的 app-bundle 卸载器提供显式确认启动，启动前完整复验签名；未知脚本不自动执行，官方工具的修改不属于本应用的恢复保证。

`ApplicationReferenceLocation` 的模型仅包含文件、行号与引用种类；配置/服务的命中文本、参数、令牌和环境变量不会进入证据、UI 或 JSON。应用页和只读接口展示图与来源信息。`ApplicationExecutionValidator` 在逐项执行前重新发现应用、重建图和管理来源；新副本、新服务或活动状态会拒绝旧计划。应用本体先移动后，原 Bundle ID 只用作关联项的归属锚点，不会把应用缺失视为删除其他副本资源的许可。

管理来源复验同时约束本体与关联项：新发现 Homebrew、其他安装管理器或服务管理时，旧计划中的缓存等关联项也拒绝移动。即使本体已经不在原路径，归属锚点仍必须通过管理来源检查；所有者证据缺失不能当作允许直接卸载。

`ContentView` 是维度操作区的唯一布局所有者。系统清理、应用卸载、较大文件和 Agent 环境在各自结果可用时统一挂载一个 `DimensionActionBar`，该组件复用 `SelectionActionBar` 的视觉布局，并根据当前维度绑定候选清理选择或应用卸载选择。各维度页面只负责内容和选择交互，不再内嵌独立底栏；`AppNavigationPolicy.showsDimensionActionBar(for:)` 是该外层承载关系的契约入口。当前维度处于等待或扫描状态时，底栏统一展示扫描进度和取消入口并禁用删除；扫描状态优先于执行状态展示。应用卸载与普通候选在执行态统一展示执行进度和停止后续项目入口，并禁用确认删除；应用批量卸载同时由 `AppModel.canExecuteUninstallBatch` 与 `executeUninstallBatch` 拒绝扫描态执行。Dashboard 的失败项安全重试在扫描期间禁用，并明确提示扫描完成后再重试。

`AppModel` 根据 `DefaultCleanupPolicy` 和用户选择构建候选集合，再由 `PlanBuilder` 生成不可变 `CleanupPlan`。“一键系统清理”只构建系统清理默认项的计划；系统模块结果发布后即可执行。应用、大文件和 Agent 环境的默认选择集合始终为空，必须手动选择。Agent 环境页按建议展示结果，按平台、范围和资源类型查询、分组，并支持删除决策。清理中心通过 `ScanDiscoverySummary` 展示应用、大文件、Agent 平台、Skill 目录和 MCP 服务器定义数量，独立于用户当前选择；扫描受限、失败和取消仍保留其真实状态。确认界面不修改文件；确认后进入真实执行。`CleanupExecutor` 不信任扫描时状态，会再次检查：

1. 计划是否过期；
2. 规则版本是否一致；
3. 路径是否仍满足 `PathPolicy`；
4. 项目是否正在使用；
5. 当前 `FileIdentity` 是否与计划一致。

任一检查失败时，对应计划或项目被拒绝/跳过，不以旧扫描结论继续写入。

计划时效在异步安全复验、活动检查、身份读取和隔离目录准备后重新检查；Helper 未处理而回退用户态前再次检查。已过期计划不得启动新的文件移动或 Helper 请求；有效期内已发出的请求继续按在途请求与不确定结果机制收敛。

## Agent Skill、MCP 与环境目录

`AgentResourcePathRegistry` 集中保存供应商路径规则，`AgentWorkspaceScanner` 通过用户级、项目级、管理员级和 `CODEX_HOME` 根目录发现资源。项目发现采用有深度和目录数量上限的只读遍历，跳过版本库元数据、依赖与构建目录。Skill 扫描只受限读取 `SKILL.md` 头部构建 `SkillCatalogEntry`；`MCPConfigurationCatalogSupport` 只从 TOML/JSON 中提取服务器名称、传输方式和项目归属，不把 command、args、env、headers、token 或 secret 放进数据模型。MCP 配置与 Skill 仍属于保护资产。

`AgentSkillCatalogPresentation` 把 Skill 与 `agentAssets` 中实际可删单元绑定，并通过 `AgentCatalogRegistry` 推断一级展示分组。用户选择“加入删除计划”时，真正进入 `selectedIDs` 的仍然是关联且当前允许删除的 cleanup units，不会绕过保护规则。MCP 分区按平台、范围和配置文件展示去敏摘要；目录分区继续展示实际路径、资源类型和目录级风险。

Agent 目录扫描的条目/深度截断、身份读取失败和目录枚举失败均携带路径限制与平台覆盖证据。深度边界仅在仍有子项未遍历时视为截断，空目录不误报；读取失败不混作预算耗尽。完整扫描与只读 JSON 共用这些证据，不把受限结果标为完成；JSON 通过 `agent_provider_coverage` 保留平台状态。

大文件扫描优先使用 Spotlight 元数据索引。索引成功后直接发布文件级结果，不再额外启动一次从 Home 目录开始的精确递归；只有 Spotlight 不可用时才回退到精确目录扫描。系统协调器对生产扫描设置有限深度和条目预算，避免大文件与 Agent 环境同时扫描时无限占用磁盘 I/O；底层扫描器仍支持显式传入 `nil` 预算用于诊断和测试。

## 执行日志 → 执行 → 历史 → 调度

项目产物由独立 `ProjectArtifactScanner` 和专项页面管理扫描，不混入一键系统清理。`ProjectScanRootsStore` 持久化自定义根，默认包含常见项目位置及 `AgentResourcePathRegistry` 集中维护的 worktree 容器。扫描根据项目 manifest 聚合五类产物，使用只读 Git 索引判断 tracked 内容，不调用构建脚本或仓库 hook；嵌套 `.git`、部署密钥、不可读内容或检查预算耗尽使候选 blocked。近期产物默认保留，仍可在工具不活动且检查通过时显式选择。

项目活动通过受限进程清单和构建工具打开的路径关联，无法完成探测时拒绝清理；不会因为其他项目存在同名工具而一概判活跃。执行前重读扫描根、manifest、Git 跟踪状态、密钥、目录内容与活动状态，之后复用既有 journal、隔离、历史、恢复和保留策略。依赖目录内的链接随目录移动，但不遍历、不统计也不删除链接目标。

真实执行由 `CleanupExecutionCoordinator` 串联，顺序是：

1. `ExecutionJournalStore.upsert` 先原子写入待执行日志；
2. `CleanupExecutor.execute` 将通过复验的项目移入 App 自有隔离目录，并验证源/目标状态；
3. `HistoryStore.upsert` 原子保存 `OperationReceipt`；
4. `QuarantineMaintenanceCoordinator.register` 按保留策略写入 `QuarantineScheduleStore`；
5. 仅在历史和调度均完成后删除执行日志。

协调器在写执行日志前同时检查待处理日志与历史，已出现过的 `planID` 会立即拒绝，避免同一计划再次关联到旧隔离目标。如果 App 在中途退出，启动时 `recoverPendingExecutions` 根据源路径与隔离路径的真实状态重建回执。若历史已写入但调度尚未完成，则复用已持久化回执补齐调度，避免重复执行文件移动。

## 历史、恢复与隔离调度

历史回执记录每项结果及总体状态。恢复和彻底删除在文件副作用前先写 `resolution-journal.json`，其中保存操作类型、源回执、源路径以及恢复目标；冲突恢复目标由 resolution ID 稳定生成。历史与调度完成更新后才移除日志。启动恢复会重放未完成 resolution，根据持久化目标和当前文件状态补写历史，避免文件已处理但记录永久停留在隔离状态。

恢复只接受属于对应计划和候选的隔离路径；原路径冲突时恢复到相邻新路径，不覆盖现有内容。彻底删除也只处理回执拥有的隔离内容。恢复、手动彻底删除、自动维护和重新调度按 receipt ID 使用同一生命周期互斥；文件处理完成后、提交历史前重新读取最新回执，避免并发操作以旧快照覆盖新状态。若 purge 日志证明源在删除准备时存在，而启动恢复时该源已缺失，则该持久化删除意图收敛为 `permanentlyDeleted`；若准备时源本就缺失则保持失败。任何未解析结果都保留 resolution journal，只有全部项目进入对应终态且历史、调度持久化后才清除。

`QuarantineScheduleStore` 保存保留策略、到期时间、最近尝试时间和自动删除失败原因。`AppModel.bootstrap()` 在启动后恢复未完成执行、迁移缺失调度并处理到期项，之后每 60 秒检查一次。失败项继续保留在隔离区，并记录：

- 稳定错误码 `itemDeletionFailed`；
- 首个具体错误消息；
- 失败项目数量；
- 最近尝试时间。

待执行日志的后台复验也参与同一 receipt 生命周期互斥，并在获得互斥后读取最新历史。复验提交不覆盖已有保留策略、到期时间或失败重试元数据；仅在缺少调度时补建，无隔离内容时移除调度，避免恢复后旧隔离状态或旧保留策略被重新写回。

自动删除在更新历史前先把本次尝试及 `historyPersistenceFailed` 结构化状态写入调度；即使历史提交失败，`lastAttemptAt` 仍然持久化。到期查询对已有失败采用 1 小时重试间隔，因此不会每分钟重复执行；App 关闭期间没有常驻服务，下次启动后继续补偿。

自动清理结果以 `standardizedFileURL.path` 作为跨模块身份键。某一路径成功后，`AppModel` 会同步清除系统清理、应用卸载、较大文件和 Agent 模块中指向该路径的所有 UUID 选择，将所有别名加入当前扫描的默认队列排除集合，并移除同路径旧失败状态，防止同一文件被不同模块重复清理。

## 集成状态与生产验收边界

### Helper

Helper 使用 macOS 13+ `SMAppService.daemon` 注册 / 异步移除，plist 位于 `Contents/Library/LaunchDaemons`，`BundleProgram` 指向同一已签名应用中的可执行文件；不使用 SMJobBless 或直接写系统启动目录。设置页分别展示系统批准、连接验证和操作会话授权，不把注册成功当作可执行。升级后提供先移除再注册的入口，失败保持未启用；移除始终保留恢复内容且无许可门禁。

`HelperSigningIdentity` 从运行代码签名取得正式 Bundle ID 和 Team ID；ad-hoc、示例身份和调试可附加签名不作为根文件操作身份。客户端与 Listener 使用公开 `NSXPCConnection.setCodeSigningRequirement` 对每条对端消息约束精确标识符、Apple 证书链和同一团队，不做 PID-only 验证，也不调用私有 auditToken。Listener 从连接有效 UID 和系统账户数据库派生范围，客户端不能指定他人 Home。

用户需先显式验证协议 v2 连接并通过系统管理员授权，内存会话最多 5 分钟；每次请求还绑定短期 token、操作摘要、planID、UID、文件身份和全进程去重 nonce。AuthorizationExternalForm 仅经 XPC 传递，不写入日志、历史或磁盘。Helper 独立检查系统授权，根进程不弹授权 UI、不代为取得新权限。

`HelperFileOperations` 只允许标准应用目录的应用隔离，以及本用户恢复区中对应计划应用的恢复 / 清除。路径逐段以目录描述符和 O_NOFOLLOW 打开；拒绝跳转语法、链接祖先、符号链接应用、非本用户恢复容器、网络文件系统、挂载点、身份变化和目标冲突。移动使用不覆盖的 renameatx_np；清除以 fd 相对 unlinkat 删除链接本身，不跟随目标，且有条目、深度和时间限制。没有任意系统删除、脚本、服务终止、chmod/chown 或跨卷复制接口；系统服务仍交回原安装来源处理。

`CleanupExecutor` 通过 `PrivilegedApplicationOperations` 接入，在已授权会话中对应用本体调用 Helper；未授权只尝试既有用户态路径，权限错误不会触发自动提权或重试。移动、恢复均验证移动后的身份。取消已发出的修改请求会等待该项结论，只停止后续项目。连接中断 / 超时或无法判断的移动结果设置 `verificationNotBefore`，保留执行日志和确定的隔离目标，待所有可能的在途请求过期后只读复验；迟到完成回写原回执，不重复移动。启动以及空闲维护期间复验；运行中的计划不参与恢复重放。

以上已通过本地临时目录、协议与执行契约及打包门禁，但尚未在真实正式签名 / 公证版本上安装、授权或完成双向认证连接。实际生产行为仍是独立发布验收条件，不得用契约或 self-check 替代。

实现依据：[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice?language=objc)、公开 macOS 15.5 SDK 的 SMAppService/NSXPCConnection 头文件，以及 [Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)。本机契约使用 Security 框架实际编译 requirement；`exists` 对布尔 false 的语义用于拒绝调试可附加签名。签名身份不是客户端提供的自由文本。

### RuleStore

`CleanupRuntime` 从 `RuleStore.currentPack()` 获取当前已验证规则，缺少已安装更新时加载随包 `bundled-3`。`CleanupRuleEngine` 按来源、系统版本、粒度、活动工具、目录完整性、保护例外、年龄及默认选择生成候选。每条规则独立扫描，一条规则失败不丢弃其他规则的已验证结果。更精确目录规则覆盖宽泛发现规则。未知缓存默认保留；uv 管理缓存禁止直接移动。

`AppInfrastructure` 是 GUI 的构造 seam：它隐藏文件系统、规则运行时、隔离执行器、历史/日志/调度存储及 Helper 授权适配器的装配。`HelperSettingsModel` 独立拥有 Helper 注册、XPC 身份验证、短时授权、撤销和升级前停用状态；`AppModel` 只保留跨功能产品状态与互斥策略。

规则执行身份由版本、规范化内容摘要与持久激活 ID 组成；摘要以结构化字段编码，保留字符串 / 数组边界。同版本换包、撤销、显式回滚均使旧计划失效，重复读取同一已安装包身份稳定。执行器在计划入口及每个项目前重读当前规则，重新验证活动与目录内容，不依赖 UI 快照。

`RuleStore` 以单个 `state.json` 原子切换当前和上一份签名包；首次提交前先持久化等价 baseline，避免写入失败留下仅 marker 的不可用状态。签名 high-water pack 防止旧源重放；历史撤销保存完整签名证据，后续包遗漏撤销或用户回滚都不能复活已撤销规则。发布者发送累计撤销时可压缩旧证明；包、证明数量和状态文件都有大小限制。原 current/previous 格式只读兼容，显式更新时迁移；已初始化状态缺失不降回旧格式或随包规则。当前包验签失败时仍可显式切回可信上一份；损坏的上一份不作为可用回滚目标。

`RuleUpdateService` 将网络下载、文件导入、验签、安全 schema、单调发布时间和原子提交接成同一流程。`HTTPSUpdateTransport` 使用 ephemeral URLSession 和流式文件输出，逐跳限制 HTTPS/443/明确主机、重定向数量、响应、字节和累计时限；无 Cookie、持久缓存或凭据，不覆盖现有输出，失败 / 取消移除其部分文件。TLS 校验交给系统，不接受自定义信任覆盖。网络行为以 URLProtocol 代送响应验证真实 delegate 路径；尚未连接用户实际发布源或验证其 TLS 部署。

应用更新由固定版本 Sparkle 2.10.0 承担下载、DMG Ed25519 校验、挂载、Apple 代码签名完整性、原生安装授权和原子替换/安装失败恢复；移除原来无人调用的 JSON `UpdateService` 骨架，不维护第二套安装器。`ApplicationUpdatePolicy` 同时供生产 delegate 与发布预检使用：只接受已验证签名 feed、严格递增整数 CFBundleVersion、明确 HTTPS 主机和完整应用 DMG，拒绝 ZIP、包安装器、增量和不合理声明长度。SDK 负责 OS/硬件适配。自动检查、下载、系统画像、远程 release notes 和 JavaScript 禁用；签名 feed 失败不设超时放行。

`ApplicationUpdateModel` 仅在正式身份/公开配置/Info.plist 一致时允许显式操作。与扫描、清理、恢复、规则激活互斥；先撤销会话并异步解除 Helper 注册，失败就不检查更新。`ImmediateUpdateDriver` 不提供延期安装；应用 delegate 在准备阶段拒绝普通退出，防止 Sparkle 的退出安装路径绕过最后确认。最后明确批准安装后才允许退出；失败/取消解锁，Helper 始终需在设置中手动重新启用，恢复记录不改写。

信任边界：运行时信任配置的 Ed25519 公钥，SDK 保留其证书轮换语义，并非额外实现了“每次安装必须与旧版同 Team ID”的验证。发行门禁独立要求主 App / CLI / Helper / Sparkle 嵌套代码均为配置 Team 的 Developer ID、Hardened Runtime 和安全时间戳，并验证公证/staple/Gatekeeper。SDK 的 Gatekeeper 预热不等于强制公证验证。应用下载使用 SDK 传输，不承诺规则下载模块的逐跳主机、累计时限或流式容量限制；归档声明长度限制及签名校验不能冒充网络资源限制。实际证书、线上源和干净机升级仍待验收。

`SignedApplicationRelease` 是离线发布门禁，不是运行时更新器：用公开配置验证官方 Sparkle 签名 XML 格式、单版本 metadata 与 DMG 签名/长度，生成 SHA256；拒绝 DTD、元数据歧义和链接归档。`publish-release.sh` 创建不覆盖的 staging，明确 `--publish` 才访问签名 Keychain、签名 DMG 并提交 Apple 公证；只输出本地产物，不发布到网络。`LOCAL-GATES-PASSED` 不替代干净机验收。

设置页显示更新来源、签名下载、离线导入、取消及确认回滚。更新操作与扫描、清理、恢复、Helper 修改、后台维护互斥；未决文件操作先复验。成功激活清空旧扫描、选择和项目确认，重复的当前包不清空状态。执行器仍独立重读磁盘，不把 UI 互斥当作安全依据。

`ReleaseConfiguration` 只接受正式身份、公开 Ed25519 公钥和无凭据的明确更新源；未知字段（含私钥字段）、源 URL query/userinfo 和无效主机均拒绝。GUI 与打包 CLI 使用同一配置，避免 CLI 以空公钥读取已安装签名包。配置仅在显式提供时嵌入 App 并受外层签名封装，默认不包含示例配置。应用更新的完整流程与发布验收仍待下一批。

`ProtectionStore` 原子保存用户保护路径，`ProtectionPolicy` 检查字面路径、当前解析路径与加入保护时的解析路径；父/子目录重叠都会阻止整体删除。GUI 设置可添加和取消保护，候选列表可右键保护。扫描结果、计划及执行使用同一策略；执行每项前重读磁盘，读取失败或清单不是普通文件时拒绝删除。默认还保护凭证、钥匙串和 App 自有恢复数据。

安装包发现通过 `InstallerDiscovery` 遍历多个已知下载来源，跳过后代符号链接，显式根链接可解析。ZIP 只读取清单、验证安装结构和完整性，不解压内容到磁盘。目录安装包计量遵守同一预算，累计超时/条目耗尽/遍历失败会丢弃该次安装包结果。

### 发布状态

构建脚本产生的本地产物使用 ad-hoc 签名，用于本机结构、嵌入和行为验证。ad-hoc 签名不等于 Developer ID 签名，不包含公证、staple、Gatekeeper 干净机验证或可交付安装流程。发布门禁见 [`docs/development.md`](development.md)。
