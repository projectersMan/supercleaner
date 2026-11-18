# 0.5.0 独立发布审查

基准：`1062a42d4aeeb94f9734e6acea794747cc89cbbf`。范围：当前相对 HEAD 的全部生产源码变更、新增源码、相关测试与发布脚本；版本目标为 `0.5.0 (145)`。

## 结论

未发现有充分证据的 Critical / Important 发布阻断问题。本报告不把未复现的假设、重构偏好或历史问题计为发布缺陷。

重点核对结果：

- 六个模块拥有各自状态和任务标识，结果页按本模块的 waiting/scanning 展示进度；其他模块发布和最终合并不会重新清空已经完成模块的选择。
- 项目默认选择初始关闭；tracked 产物允许手动审查，开启设置才加入项目默认队列。未知 Git、凭据、嵌套仓库目录、活动项目和永久保护仍拒绝执行；目录和子安装包的选择同步避免取消子项后仍通过父目录清理。
- 项目内 DMG 在大文件候选发布前识别归属，项目候选保留重复副本证明；被证明必须保留的文件及包含它的父目录不能进入执行计划。
- 本地 AI 模型始终要求手动选择，不进入全部默认项；移动前重新核验存储范围、内容指纹、文件身份、活动进程和保护策略。
- 全部默认项先校验原始候选与副本证明，再合并别名和父子操作；渐进结果的已有选择、清理回执和最终汇总有对应回归覆盖。
- Trash 允许扫描期间操作；关闭窗口的延后提醒监听父模型与 Helper，完成结果页可解除门禁；关闭提醒具有持久化“不再提醒”，主动操作始终确认；明确退出时 Cancel/操作失败不否决退出，获准操作及容量刷新完成后才回复终止。
- 应用首次进入避免构建全量卸载计划；单项与批量计划共用经过保护检查的缓存，报告与保护变更使缓存失效；空选择汇总保留安装 receipt 单选语义。
- 显式版本使用精确目标，普通构建仍只递增 patch；数值版本比较拒绝同版/降级，环境版本必须匹配解析后的目标，环境 build 必须大于旧 build；所有拒绝路径均在保存之前，CLI 测试覆盖非法目标不写文件及显式发布后继续常规递增。

## 本次审查直接执行的检查与边界

- `git diff --check`：通过。
- `zsh -n Scripts/build-app.sh Scripts/verify-app.sh Scripts/check-production-signing.sh`：通过。
- 阅读版本单测全部 13 项及主代理提供的本轮通过结果；本审查未另外执行会生成素材的测试。
- 阅读新增核心测试、AppModel/Trash 受控自检及既有验证日志；未独立编译全套、未启动真实 GUI、未清空真实废纸篓、未清理或退出用户应用、未提交或推送。
- 最终 `0.5.0 (145)` 构建、签名、DMG/LFS 上传和远程一致性需要以主代理本轮实际执行结果为准；本报告不以历史日志代替本轮产物验证。
- 根目录 `AGENTS.md` 与 `.trae/rules/project_rules.md` 不存在，本审查未假定其中有额外规则。

## 按文件的修改必要性摘要

下表逐一记录本次源码、测试源码及构建配置变更的目的；删除项也计入，便于对照 diff 复核。

| 文件 | 必要性 |
| --- | --- |
| [Package.swift](../../Package.swift) | 移除已撤下的 CLI product/target，保持实际构建与 GUI/Core 的交付范围一致。 |
| [Resources/AppInfo.plist](../../Resources/AppInfo.plist) | 为确认后的 Finder Apple Events 操作声明系统授权用途。 |
| [Resources/App.entitlements](../../Resources/App.entitlements) | 赋予签名应用执行 Finder 自动化所需的 Apple Events entitlement。 |
| [Resources/en.lproj/InfoPlist.strings](../../Resources/en.lproj/InfoPlist.strings) | 为英文系统授权弹窗提供 Finder 清空用途说明。 |
| [Resources/zh-Hans.lproj/InfoPlist.strings](../../Resources/zh-Hans.lproj/InfoPlist.strings) | 为中文系统授权弹窗提供 Finder 清空用途说明。 |
| [Scripts/build-app.sh](../../Scripts/build-app.sh) | 在构建时分配精确或常规版本，统一 SDK 元数据和 Finder 授权签名，并取消 CLI 打包。 |
| [Scripts/check-production-signing.sh](../../Scripts/check-production-signing.sh) | 从签名验收清单移除已取消的 CLI，继续覆盖实际交付的可执行文件。 |
| [Scripts/verify-app.sh](../../Scripts/verify-app.sh) | 检查 Finder 授权、链接 SDK 与最低版本，并运行新增 Trash 自检。 |
| [Scripts/version.py](../../Scripts/version.py) | 提供构建即保存和显式精确版本入口，并防止版本降级、同版及 build 回退。 |
| [Version.json](../../Version.json) | 记录本次实际构建的 `0.5.0 (145)` 发布身份。 |
| `Sources/CleanerApp/AgentEnvironmentProgressView.swift`（删除） | 以通用 ModuleProgressView 替换专属进度布局，统一六模块呈现。 |
| [Sources/CleanerApp/AgentEnvironmentView.swift](../../Sources/CleanerApp/AgentEnvironmentView.swift) | 将扫描、列表准备和空结果状态接入统一模块进度。 |
| [Sources/CleanerApp/AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 管理六模块队列、项目设置、资源筛选、容量、Trash 门禁及应用计划缓存，并补足对应受控回归。 |
| [Sources/CleanerApp/ApplicationsView.swift](../../Sources/CleanerApp/ApplicationsView.swift) | 在应用模块等待或扫描时显示本模块进度。 |
| [Sources/CleanerApp/CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 共享 Trash 控制器并让明确退出等待已批准的可选清空任务。 |
| [Sources/CleanerApp/CleanupActionBars.swift](../../Sources/CleanerApp/CleanupActionBars.swift) | 将清理中心动作和统计扩展为各模块仍被选中的全部默认项。 |
| [Sources/CleanerApp/CleanupReviewView.swift](../../Sources/CleanerApp/CleanupReviewView.swift) | 将系统清理结果页接入独立模块进度分支。 |
| [Sources/CleanerApp/Components.swift](../../Sources/CleanerApp/Components.swift) | 共用侧栏表面样式并补充本地模型来源展示。 |
| [Sources/CleanerApp/ContentView.swift](../../Sources/CleanerApp/ContentView.swift) | 加入模型/项目入口、侧栏容量和 Trash/目录配置期间的交互门禁。 |
| [Sources/CleanerApp/DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 展示六模块默认量与独立状态，并提供紧凑的累计清理和手动 Trash 入口。 |
| [Sources/CleanerApp/DiskSpaceView.swift](../../Sources/CleanerApp/DiskSpaceView.swift) | 在大文件模块扫描时统一显示独立进度，避免旧结果掩盖当前状态。 |
| [Sources/CleanerApp/ModuleProgressView.swift](../../Sources/CleanerApp/ModuleProgressView.swift) | 为六模块提供相同布局与可访问性语义的进度组件。 |
| [Sources/CleanerApp/PermissionsView.swift](../../Sources/CleanerApp/PermissionsView.swift) | 暴露项目扫描目录、项目预选和 Trash 提醒偏好，并显示保存失败。 |
| [Sources/CleanerApp/ResourceCleanupPresentationFixture.swift](../../Sources/CleanerApp/ResourceCleanupPresentationFixture.swift) | 为项目/模型列表、默认选择和安装包迁移提供可重复的受控数据。 |
| [Sources/CleanerApp/ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 为本地模型与项目资源提供分组、筛选、排序、选择和保护证据界面。 |
| [Sources/CleanerApp/ScanAccessTracking.swift](../../Sources/CleanerApp/ScanAccessTracking.swift) | 识别新增 payload，保留模型/项目自身报告的限制状态。 |
| `Sources/CleanerApp/SidebarToolbarAlignment.swift`（删除） | 移除旧的原生工具栏对齐补丁，由当前 SDK 元数据及布局承担。 |
| [Sources/CleanerApp/TrashEmptyingCheck.swift](../../Sources/CleanerApp/TrashEmptyingCheck.swift) | 以注入执行器验证取消、防重、失败、容量刷新及退出时序，避免发送 Finder 清空命令。 |
| [Sources/CleanerApp/TrashReminderController.swift](../../Sources/CleanerApp/TrashReminderController.swift) | 统一手动/关闭/退出清空确认与执行，并只在 Finder 明确确认后记录成功。 |
| [Sources/CleanerApp/TrashReminderWindowObserver.swift](../../Sources/CleanerApp/TrashReminderWindowObserver.swift) | 将窗口关闭交给共享控制器处理延后提醒和繁忙门禁。 |
| `Sources/CleanerCLI/main.swift`（删除） | 撤下独立命令行入口，使交付范围与产品要求一致。 |
| [Sources/CleanerCore/AppNavigationPolicy.swift](../../Sources/CleanerCore/AppNavigationPolicy.swift) | 将模型和项目纳入导航、结果路由与维度动作栏策略。 |
| [Sources/CleanerCore/BoundedProcess.swift](../../Sources/CleanerCore/BoundedProcess.swift) | 将项目目录活动与具体打开文件分开，允许审查未打开的项目安装包。 |
| [Sources/CleanerCore/CleanupReportReconciliation.swift](../../Sources/CleanerCore/CleanupReportReconciliation.swift) | 在清理回执合并时同步移除模型/项目候选并保留其覆盖范围。 |
| [Sources/CleanerCore/CleanupRuntime.swift](../../Sources/CleanerCore/CleanupRuntime.swift) | 为项目活动和本地模型提供生产配置及执行前重新验证入口。 |
| [Sources/CleanerCore/CleanupScopePolicy.swift](../../Sources/CleanerCore/CleanupScopePolicy.swift) | 将本地模型与项目候选按来源独立分流。 |
| [Sources/CleanerCore/CleanupSessionSummary.swift](../../Sources/CleanerCore/CleanupSessionSummary.swift) | 将清理结果准确归属项目或本地模型模块。 |
| [Sources/CleanerCore/DefaultCleanupPolicy.swift](../../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 汇总仍选中的默认项、排除手动模型，并在执行合并前验证完整证明。 |
| [Sources/CleanerCore/DiskCapacitySnapshot.swift](../../Sources/CleanerCore/DiskCapacitySnapshot.swift) | 以独立文件系统测量提供可用容量及明确读取失败状态。 |
| [Sources/CleanerCore/Execution.swift](../../Sources/CleanerCore/Execution.swift) | 在可能挂起的准备和 Helper 回退后，再次验证本地模型身份与内容。 |
| [Sources/CleanerCore/LargeFileCleanupProof.swift](../../Sources/CleanerCore/LargeFileCleanupProof.swift) | 让项目 DMG 继续携带并验证原有保留副本证明。 |
| [Sources/CleanerCore/LargeFileContentAnalyzer.swift](../../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 对安装包采用对应范围判断，并允许 tracked 项仅走明确手动快照。 |
| [Sources/CleanerCore/LocalAIModelScanner.swift](../../Sources/CleanerCore/LocalAIModelScanner.swift) | 扫描固定模型布局并以指纹、权限、预算、活动和凭据检查保证手动清理边界。 |
| [Sources/CleanerCore/Models.swift](../../Sources/CleanerCore/Models.swift) | 增加模型来源，并禁止模型执行沿用可变缓存的宽松身份策略。 |
| [Sources/CleanerCore/ProjectArtifacts.swift](../../Sources/CleanerCore/ProjectArtifacts.swift) | 发现项目 DMG、支持 tracked 人工选择并保留活动、凭据、Git 和执行复验边界。 |
| [Sources/CleanerCore/ProjectInstallerOwnership.swift](../../Sources/CleanerCore/ProjectInstallerOwnership.swift) | 集中处理项目安装包归属、保留副本与父目录保护及大文件树去重。 |
| [Sources/CleanerCore/ProtectionPolicy.swift](../../Sources/CleanerCore/ProtectionPolicy.swift) | 批次复用保护根的解析结果，同时继续核验每个候选的当前物理路径。 |
| `Sources/CleanerCore/ReadOnlyInterface.swift`（删除） | 移除已取消的 CLI JSON/请求接口，保留共享 Core 的实际扫描与计划能力。 |
| [Sources/CleanerCore/ResourceCleanupListPolicy.swift](../../Sources/CleanerCore/ResourceCleanupListPolicy.swift) | 共用项目/模型的可选择边界、筛选和排序逻辑。 |
| [Sources/CleanerCore/Resources/en.lproj/Localizable.strings](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 为新增六模块、资源、设置、容量和 Trash 流程提供英文文案。 |
| [Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 为新增六模块、资源、设置、容量和 Trash 流程提供中文文案。 |
| [Sources/CleanerCore/ScanDiscoverySummary.swift](../../Sources/CleanerCore/ScanDiscoverySummary.swift) | 将模型资源数和项目产物数纳入扫描发现摘要。 |
| [Sources/CleanerCore/Scanner.swift](../../Sources/CleanerCore/Scanner.swift) | 在扫描上下文中区分一般活动路径与项目构建活动。 |
| [Sources/CleanerCore/SystemCleanupScanner.swift](../../Sources/CleanerCore/SystemCleanupScanner.swift) | 更新注释以准确描述撤下 CLI 后的共享扫描职责。 |
| [Sources/CleanerCore/SystemScanCoordinator.swift](../../Sources/CleanerCore/SystemScanCoordinator.swift) | 调度新增模块、传播取消，并在发布大文件前排除项目 DMG。 |
| [Sources/CleanerCore/SystemScanPrimitives.swift](../../Sources/CleanerCore/SystemScanPrimitives.swift) | 将模型和项目定义为具有独立生命周期的正式扫描模块。 |
| [Sources/CleanerCore/SystemScanReport.swift](../../Sources/CleanerCore/SystemScanReport.swift) | 在渐进、最终及快照报告中完整保留新增 payload、覆盖范围和项目安装包证明。 |
| [Sources/CleanerCore/TrashReminderState.swift](../../Sources/CleanerCore/TrashReminderState.swift) | 分离持久化提醒抑制与本次清空成功确认，防止取消/失败误记成功。 |
| [Sources/CoreContractChecks/AppNavigationContract.swift](../../Sources/CoreContractChecks/AppNavigationContract.swift) | 验证六模块导航路由、动作栏和终态扫描控制。 |
| [Sources/CoreContractChecks/CoreReadOnlyContract.swift](../../Sources/CoreContractChecks/CoreReadOnlyContract.swift) | 使用生产 Core 替代 CLI 检查只读扫描、计划预览、历史读取和永久保护。 |
| [Sources/CoreContractChecks/PackagedRuleConfigurationContract.swift](../../Sources/CoreContractChecks/PackagedRuleConfigurationContract.swift) | 在无 CLI 的实际打包资源布局下验证签名规则和只读行为。 |
| [Sources/CoreContractChecks/ProjectArtifactContract.swift](../../Sources/CoreContractChecks/ProjectArtifactContract.swift) | 更新 tracked 产物为人工审查语义，同时继续验证其余保护边界。 |
| `Sources/CoreContractChecks/ReadOnlyInterfaceContract.swift`（删除） | 删除随 CLI 接口撤下而失去对象的契约。 |
| [Sources/CoreContractChecks/ReviewRegressionContract.swift](../../Sources/CoreContractChecks/ReviewRegressionContract.swift) | 将完整性回归迁移到直接 Core 检查，并把素材统一放入 Tests。 |
| [Sources/CoreContractChecks/main.swift](../../Sources/CoreContractChecks/main.swift) | 注册 Core 只读与打包规则配置的新契约入口。 |
| [Tests/CleanerCoreTests/DefaultCleanupSelectionTests.swift](../CleanerCoreTests/DefaultCleanupSelectionTests.swift) | 验证项目设置、模型排除、自动 Agent 默认项及副本证明与合并顺序。 |
| [Tests/CleanerCoreTests/DiskCapacitySnapshotTests.swift](../CleanerCoreTests/DiskCapacitySnapshotTests.swift) | 验证容量快照边界、无效输入和真实文件系统读取结果。 |
| [Tests/CleanerCoreTests/DuplicateLargeFileTests.swift](../CleanerCoreTests/DuplicateLargeFileTests.swift) | 将重复文件回归适配六模块默认选择构造。 |
| [Tests/CleanerCoreTests/LocalAIModelExecutionTests.swift](../CleanerCoreTests/LocalAIModelExecutionTests.swift) | 验证模型移动前的修改、活动、身份、规则和权限准备竞态均会被拒绝。 |
| [Tests/CleanerCoreTests/LocalAIModelScannerTests.swift](../CleanerCoreTests/LocalAIModelScannerTests.swift) | 验证各模型布局、凭据、链接、活动、预算及完整性保护。 |
| [Tests/CleanerCoreTests/NewCleanupDimensionsTests.swift](../CleanerCoreTests/NewCleanupDimensionsTests.swift) | 验证模型/项目在导航、报告和渐进扫描中的端到端数据归属。 |
| [Tests/CleanerCoreTests/ProjectInstallerTests.swift](../CleanerCoreTests/ProjectInstallerTests.swift) | 验证 DMG 归属、tracked 手选恢复、活动、配置根和保留副本父目录保护。 |
| [Tests/CleanerCoreTests/ProtectionPolicyBatchTests.swift](../CleanerCoreTests/ProtectionPolicyBatchTests.swift) | 验证批量保护与单项一致，并覆盖链接重定向和不可读策略。 |
| [Tests/CleanerCoreTests/ResourceCleanupListPolicyTests.swift](../CleanerCoreTests/ResourceCleanupListPolicyTests.swift) | 验证资源可选择判定、范围筛选及大小/目录/选择排序。 |
| [Tests/CleanerCoreTests/TrashReminderStateTests.swift](../CleanerCoreTests/TrashReminderStateTests.swift) | 验证仅成功清空确认累计字节，抑制偏好独立持久化且可恢复。 |
| [Tests/test_version.py](../test_version.py) | 覆盖常规与精确发布版本、错误不写入和环境 build 单调递增。 |
| [Tests/application-first-entry/IconFirstEntry.swift](../application-first-entry/IconFirstEntry.swift) | 隔离测量应用图标首次加载耗时，支持首次进入性能定位。 |
| [Tests/application-first-entry/install-and-check.py](../application-first-entry/install-and-check.py) | 留存该轮构建、安装与 DMG 的版本、签名、授权和可执行文件一致性验收。 |
| [Tests/cleanup-center-resource-sync/check-doc-links.py](../cleanup-center-resource-sync/check-doc-links.py) | 验证资源同步改动涉及的当前文档本地路径链接。 |
| [Tests/cleanup-center-resource-sync/install-and-check.py](../cleanup-center-resource-sync/install-and-check.py) | 验证资源同步版本在构建、安装和 DMG 三处的产物一致性。 |
| [Tests/close-trash-reminder-choice/check-artifacts.py](../close-trash-reminder-choice/check-artifacts.py) | 验证关闭提醒版本的构建与 DMG 一致性，并避免替换既有安装。 |
| [Tests/dashboard-sidebar-footer/SidebarMaterialProbe.swift](../dashboard-sidebar-footer/SidebarMaterialProbe.swift) | 以原生探针检查侧栏底部容量区材质与布局。 |
| [Tests/dashboard-sidebar-footer/install-and-check.py](../dashboard-sidebar-footer/install-and-check.py) | 验证侧栏容量版本在构建、安装及 DMG 中的产物一致性。 |
| [Tests/exact-trash-dialog/check-source.sh](../exact-trash-dialog/check-source.sh) | 静态断言手动、关闭和退出复用一个确认工厂和执行器。 |
| [Tests/exact-trash-dialog/main.swift](../exact-trash-dialog/main.swift) | 通过受控原生窗口验证双按钮确认、关闭提醒及抑制选项。 |
| [Tests/exact-trash-dialog/run-native-check.sh](../exact-trash-dialog/run-native-check.sh) | 编译并运行上述受控原生弹窗回归。 |
| [Tests/local-ai-projects-disk/disk/main.swift](../local-ai-projects-disk/disk/main.swift) | 独立验证容量测量与错误边界，避免依赖真实清理回执。 |
| [Tests/module-progress-trash-reminder/check-artifacts.py](../module-progress-trash-reminder/check-artifacts.py) | 验证模块进度/Trash 版本的构建和 DMG 内容一致。 |
| [Tests/project-installer-discovery/AlignmentProbe.swift](../project-installer-discovery/AlignmentProbe.swift) | 保留原生布局对齐诊断探针以解释该轮视觉验证。 |
| [Tests/project-installer-discovery/check-doc-links.py](../project-installer-discovery/check-doc-links.py) | 验证项目安装包说明涉及的当前文档链接。 |
| [Tests/project-installer-discovery/install-and-check.py](../project-installer-discovery/install-and-check.py) | 验证项目 DMG 归属版本在构建、安装和 DMG 中一致。 |
| [Tests/project-selection-preferences/install-and-check.py](../project-selection-preferences/install-and-check.py) | 验证项目选择设置版本的实际安装与打包一致性。 |
| [Tests/release-0.5.0/check-artifacts.py](check-artifacts.py) | 核对本次 0.5.0 构建与只读挂载 DMG 的版本、签名、授权和可执行文件哈希，并保留既有安装。 |
| [Tests/quit-without-emptying/install-and-check.py](../quit-without-emptying/install-and-check.py) | 验证 Cancel 可退出版本的实际安装与打包一致性。 |
| [Tests/quit-without-emptying/main.swift](../quit-without-emptying/main.swift) | 在受控原生终止流程中验证 Cancel 保留 Trash 且允许退出。 |
| [Tests/quit-without-emptying/run-native-check.sh](../quit-without-emptying/run-native-check.sh) | 抽取生产 delegate 运行 Cancel 退出回归，避免复制另一套终止逻辑。 |
| [Tests/trash-during-scan/check-artifacts.py](../trash-during-scan/check-artifacts.py) | 验证扫描期间 Trash 版本的构建与 DMG 内容一致。 |
| [Tests/trash-exit-reuse/check-appkit-termination.py](../trash-exit-reuse/check-appkit-termination.py) | 验证真实 AppKit terminateLater/reply 循环等待受控清空而不触发 Finder。 |
| [Tests/trash-exit-reuse/install-and-check.py](../trash-exit-reuse/install-and-check.py) | 验证退出复用版本在构建、安装和 DMG 中的产物一致性。 |

文档、历史测试日志和生成产物由主代理在最终提交清单中统一核对；本审查没有发现需要追加生产代码重构的发布理由。
