# 六维度清理与卷容量验证

基线 `1062a42`，本批版本 0.4.4（118）。按用户要求将本地 AI 模型、项目产物作为与 Agent 环境并列的独立维度，清理中心补充卷容量，并移除无 GUI 依赖的独立用户 CLI。本文件记录逐文件必要性与最终验证；所有夹具仅在本目录下创建并清理，不对真实用户模型或工程执行删除。

## 设计与复核

“项目”是有工程 manifest 的源码目录，“产物”是安装依赖或构建生成的目录。目录名、Git ignored、可重新下载都不是自动删除的充分依据。两个新维度均零预选、显式选择，复用现有计划、确认、执行、回执及恢复。

本地模型仅发现七类供应商的十个固定位置，尚不支持自定义模型根。Hugging Face 按仓库、LM Studio 按模型、Ollama 按整个共享模型库；不会按 blob 单独删除。内部软链接不跟随，候选及祖先链接拒绝；凭据、运行/未知活动、权限或预算不完整保持保护。模型指纹是目录身份与元数据快照，不是全部权重内容的哈希。

审查发现并要求修正的两点：

- P1（已修复）：模型严格禁止内容变化，却因此被旧执行器跳过移动前终验。现将终验资格与“允许内容变化”解耦，覆盖模型目录、单模型文件、隔离目录准备和 Helper 回退后的变化。
- P2（已修复）：项目选择新根后调用的刷新入口仍只有旧模块白名单。新增 AppModel 自检先观察 `resource module refresh did not start`，再允许模型/项目单模块刷新，并验证可立即取消；无报告的首次目录选择走首次全扫描。

原审查者针对两项修复再次只读复核，确认原缺口均已解决。模型及相关执行回归 31 项通过，见 [绿灯记录](model-execution-green.log)。

局部建议评分：移动前终验 100、项目根刷新 100，均在本批执行。全局建议评分：沿用统一执行/恢复链路 100、容量与清理回执口径分开 98、删除无 GUI 依赖 CLI 并保留 Core 契约 90，均在本批执行。没有为低分或未授权方向附加功能。

## 验证记录

Release 完整 XCTest 295 项、0 失败，核心契约全部通过，详见 [构建与测试日志](package.log)。语言覆盖检查通过 1229 条中英消息。

- [完整包验证](verification.log) 通过资源、签名、macOS 13 最低版本、偏好、隔离/恢复烟雾、导航刷新/取消与既有性能自检。
- 固定证书签名 App 已完成；App/Helper 均为 0.4.4（118），独立 CLI 不在包内，GUI、Helper、AgentInference 保留。
- [DMG 日志](dmg.log) 记录生成、重挂载、图标与 Applications 入口、包签名通过。首轮系统返回“资源忙”，[首轮日志](dmg-first.log) 保留；确认无本任务遗留挂载后重试同一脚本成功，未修改脚本绕过检查。
- [安装校验](installation.log)：旧 App 界面确认空闲后通过应用菜单正常退出，再替换 `/Applications/SuperCleaner.app`，三个可执行文件与构建副本 SHA256 相同，签名及版本一致。应用数据与偏好目录未替换，旧 App 临时备份已清理。
- [最终文件与链接审计](final-audit.log)：13 份变更/新增 Markdown 的本地链接无新增失效；历史 0.2.25 DMG 产物链接原样保留。`git diff --check` 通过，测试夹具与安装备份已清理。
- 原生界面已观察：固定安装路径成功启动、侧栏及首页六入口、卷总量/已用/可用（当时为 494.38 / 299.79 / 194.59 GB）、独立项目页、零选择底栏与目录选择弹窗。取消弹窗后自动化读取持续超时；[进程采样](ui-sample.txt) 显示主线程在正常 NSApplication 事件循环，未卡在 NSOpenPanel。本次没有据此修改生产逻辑，也没有声称目录提交后的实机流程或完整真实磁盘全扫描已通过。项目/模型真实 I/O、目录刷新入口、取消及清理安全分别由 Core 夹具和 AppModel 自检验证。

- [导航刷新红灯](navigation-red.log)、[导航刷新绿灯](navigation-green.log)：实际 AppModel 入口回归，没有执行用户目录扫描或清理。
- [模型扫描红灯](model-tests-red.log)、[模型扫描绿灯](model-tests-green.log)、[预算红灯](model-budget-red.log)：布局、共享存储、链接、活动、凭据、权限、预算和内容复验。
- [模型执行红灯](model-execution-red.log)：使用本地测试夹具与受控活动状态，复现早期校验后改变权重或启动工具仍被移动的问题。
- [模型执行及相关绿灯](model-execution-green.log)：31 项定向回归全部通过，包含新增 5 项模型移动安全测试。
- [维度验证红灯](dimensions-red.log)：模型必须走专属验证器，不能按系统垃圾规则查找模型规则 ID。
- [磁盘读取独立验证](disk/standalone.log) 和 [macOS 13 验证源](disk/main.swift)：容量边界、真实卷、明确错误及系统版本兼容。
- [SwiftPM 清单](cli/package.json)：独立 CleanerCLI 产品和 target 已移除；Core、App、Helper、契约工具和 AgentOverlapAI 保留。

## 逐文件 diff 审计

每项均为实现已授权范围、保留安全行为或同步文档所需；没有顺带修改其他清理规则、恢复策略或系统授权。

| 文件 | 修改与必要性 |
| --- | --- |
| [Package.swift](../../Package.swift) | 删除独立 supercleaner 产品及 CleanerCLI target；无 GUI 依赖，不新增包。 |
| `Sources/CleanerCLI/main.swift`（删除） | 删除仅用于参数解析与 JSON 输出的用户入口。 |
| `Sources/CleanerCore/ReadOnlyInterface.swift`（删除） | 删除 CLI 专属请求、响应和传输层；安全逻辑仍由 Core 提供。 |
| [LocalAIModelScanner.swift](../../Sources/CleanerCore/LocalAIModelScanner.swift) | 新增按供应商布局发现、完整性限制、人工选择、元数据指纹和执行复验。 |
| [DiskCapacitySnapshot.swift](../../Sources/CleanerCore/DiskCapacitySnapshot.swift) | 读取 Home 所在卷的 statfs 总量/可用量，校验溢出与错误，推导已用量。 |
| [SystemScanPrimitives.swift](../../Sources/CleanerCore/SystemScanPrimitives.swift) | 增加 localAIModels、projects 模块身份，使状态机完整覆盖六维度。 |
| [Models.swift](../../Sources/CleanerCore/Models.swift) | 新增模型来源并严格禁止执行期间内容变化。 |
| [AppNavigationPolicy.swift](../../Sources/CleanerCore/AppNavigationPolicy.swift) | 补齐新页面、标题/图标、结果路由、底栏、焦点与扫描控制。 |
| [CleanupScopePolicy.swift](../../Sources/CleanerCore/CleanupScopePolicy.swift) | 两个新维度按来源隔离，继续排除于系统默认范围。 |
| [SystemScanCoordinator.swift](../../Sources/CleanerCore/SystemScanCoordinator.swift) | 加入两个独立可取消任务、渐进结果、覆盖和终态；项目使用持久根目录。 |
| [SystemScanReport.swift](../../Sources/CleanerCore/SystemScanReport.swift) | 增加模型与项目 payload、候选和覆盖；渐进合并与快照保留新库存。 |
| [CleanupReportReconciliation.swift](../../Sources/CleanerCore/CleanupReportReconciliation.swift) | 成功清理后同时移除新库存和跨模块同路径候选，防止残留旧结果。 |
| [CleanupRuntime.swift](../../Sources/CleanerCore/CleanupRuntime.swift) | 模型走专属范围/指纹验证并读取真实活动状态；保留统一保护/规则门禁。 |
| [Execution.swift](../../Sources/CleanerCore/Execution.swift) | 模型目录和文件在异步准备后终验，并在 Helper 回退后再核验，拒绝变化或新活动。 |
| [CleanupSessionSummary.swift](../../Sources/CleanerCore/CleanupSessionSummary.swift) | 将成功回执量分别归属模型和项目，避免混入系统清理。 |
| [ScanDiscoverySummary.swift](../../Sources/CleanerCore/ScanDiscoverySummary.swift) | 提供两个新模块各自的发现数量与提示。 |
| [SystemCleanupScanner.swift](../../Sources/CleanerCore/SystemCleanupScanner.swift) | 清理已退役 CLI 的过时共用入口注释，不改变扫描算法。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 接入六维度、项目根选择/刷新、真实项目活动、容量异步刷新与失败状态；补实际入口回归。 |
| [ContentView.swift](../../Sources/CleanerApp/ContentView.swift) | 增加侧栏入口和页面分发。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 复用公共候选交互，模型按供应商、项目按工程分组，提供目录选择与重扫。 |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 六行范围与真实容量面板；保持累计清理量的原有口径。 |
| [Components.swift](../../Sources/CleanerApp/Components.swift) | 检查器显示模型来源名称。 |
| [ScanAccessTracking.swift](../../Sources/CleanerApp/ScanAccessTracking.swift) | 保留新模块原始限制与失败状态，避免被旧权限展示规则清除。 |
| [en Localizable.strings](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 新功能、保护原因、容量与扫描文案的英语资源。 |
| [zh-Hans Localizable.strings](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 与英语键和占位符一致的中文资源。 |
| [AppNavigationContract.swift](../../Sources/CoreContractChecks/AppNavigationContract.swift) | 扩展导航及底栏契约至六维度。 |
| [CoreReadOnlyContract.swift](../../Sources/CoreContractChecks/CoreReadOnlyContract.swift) | 直接验证 Core 的分类、计划、空历史、保护和零写入，替代 CLI 传输测试。 |
| `Sources/CoreContractChecks/ReadOnlyInterfaceContract.swift`（删除） | 删除已经无生产入口的 CLI 接口契约，安全断言迁移到直接 Core 契约。 |
| [ReviewRegressionContract.swift](../../Sources/CoreContractChecks/ReviewRegressionContract.swift) | 直接验证 Agent 深度/权限/身份覆盖，移除对旧 JSON 格式的依赖。 |
| [PackagedRuleConfigurationContract.swift](../../Sources/CoreContractChecks/PackagedRuleConfigurationContract.swift) | 契约工具自复制至测试 App，使用实际打包 Core 资源验证签名规则配置，不依赖用户 CLI。 |
| [CoreContractChecks/main.swift](../../Sources/CoreContractChecks/main.swift) | 将开发验证入口改为直接 Core 与包配置检查。 |
| [build-app.sh](../../Scripts/build-app.sh) | 移除 CLI 构建/复制/签名，保留包配置、Helper 和生产门禁。 |
| [check-production-signing.sh](../../Scripts/check-production-signing.sh) | 仅移除退役 CLI 的签名身份要求，保留其它嵌套代码检查。 |
| [LocalAIModelScannerTests.swift](../CleanerCoreTests/LocalAIModelScannerTests.swift) | 覆盖模型发现与保守拒绝边界。 |
| [LocalAIModelExecutionTests.swift](../CleanerCoreTests/LocalAIModelExecutionTests.swift) | 覆盖异步准备/回退期间内容与活动变化、不移动断言及正常路径。 |
| [DiskCapacitySnapshotTests.swift](../CleanerCoreTests/DiskCapacitySnapshotTests.swift) | 覆盖容量数学边界、真实卷读取、无效/不存在路径错误。 |
| [NewCleanupDimensionsTests.swift](../CleanerCoreTests/NewCleanupDimensionsTests.swift) | 验证独立路由、真实双模块扫描、零预选、清理后库存对账及模型专属执行验证。 |
| [Version.json](../../Version.json) | 本批递增一次至 0.4.4（118），App/Helper 同版本。 |
| [README.md](../../README.md) | 更新用户入口、项目定义、模型范围、磁盘口径及 CLI 退役说明。 |
| [doc/architecture.md](../../doc/architecture.md) | 六维度与容量架构、公共执行链和模块责任。 |
| [doc/development.md](../../doc/development.md) | 新维度接线、边界验证和开发检查入口。 |
| [docs/architecture.md](../../docs/architecture.md) | 同步既有详细架构与执行模型，移除当前 CLI 结构。 |
| [docs/development.md](../../docs/development.md) | 同步构建/签名/契约命令和模型、项目、容量开发要求。 |
| [docs/production-release-checklist.md](../../docs/production-release-checklist.md) | 加入六维度、零预选、容量口径、无 CLI 包与直接 Core 门禁。 |
| [docs/system-cleanup-scanning.md](../../docs/system-cleanup-scanning.md) | 修正当前验证接口为直接 Core 契约。 |
| [doc/agent-only-scope.md](../../doc/agent-only-scope.md) | 标记历史四模块与 CLI 约束已被新授权替代，保留历史事实。 |
| [doc/large-file-duplicates-plan.md](../../doc/large-file-duplicates-plan.md) | 更新当前共享契约链接，保留历史版本验证记录。 |
| [doc/vervain-reference-research.md](../../doc/vervain-reference-research.md) | 保留先前未跟踪研究，补充已实施与仍未覆盖的界限；未复制外部产品代码。 |
| [doc/local-ai-projects-disk-plan.md](../../doc/local-ai-projects-disk-plan.md) | 固定本次目标、实现边界、执行步骤与自我复核。 |
| 本目录记录与 [release-0.4.4.md](../../doc/release-0.4.4.md) | 留存可复查验证和交付事实，清理不必要二进制、失败夹具与安装备份。 |

根目录没有 AGENTS.md 或 .trae/rules/project_rules.md，因此没有创建或改写这些文件。项目为 Swift，本批无新增依赖，不创建空 requirements.txt。没有修改既有 .gitignore；App/DMG 沿用 build 下的生成产物约定。未提交或推送。
