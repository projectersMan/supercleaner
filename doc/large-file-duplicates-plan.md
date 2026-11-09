# 重复大文件实施与验收

清理中心和侧栏使用「重复大文件」。全量扫描、单模块刷新和取消后继续均执行大文件发现、精确查重、ZIP 核验三个顺序阶段。Spotlight 与递归发现共用后续阶段，同一次扫描发布一份大文件模块结果。入口见 [SystemScanCoordinator.swift](../Sources/CleanerCore/SystemScanCoordinator.swift)。

## 完全相同的文件

当前大文件候选按大小分桶。至少两个候选的桶才读内容。所有格式都可参加，先分块计算 SHA-256，再比较完整字节、资源叉和扩展属性。读盘前后校验文件身份和纳秒时间。文件名和扩展名可以不同。硬链接、链接路径、远程卷、已知云同步位置、占位文件、受保护或活跃的文件排除在核验范围之外。参见 [LargeFileContentAnalyzer.swift](../Sources/CleanerCore/LargeFileContentAnalyzer.swift)。

每组按稳定路径顺序保留首个可用成员，推荐一份其他副本。一个目标同时命中两类时显示一行，采用归档核验证据。归档优先纳入推荐，批次中的保留路径不会再成为其他推荐项的删除目标。

## 已解压 ZIP

核验每个符合大文件阈值的普通 ZIP 和它的同级文件夹。支持归档的单层目录直接对应同级文件夹，也支持没有外层目录的归档。大小门槛以同级文件夹内所有普通文件的逻辑字节总和为准，须达到本次大文件阈值和 ZIP 自身大小。ZIP 内的单个成员可以很小或为空。磁盘上的对应文件须与成员的未压缩大小相等。

先累加 ZIP 清单里的未压缩字节。如果总和达不到门槛，任何与清单一致的文件夹也达不到，可以直接跳过。总和通过门槛后，按路径、类型和大小检查同级文件夹，完整匹配的目录才分块解码并逐字节比较。这样可以在解码前排除小目录，且无需额外遍历磁盘计算文件夹大小。目录里的额外文件、缺失条目、内容变化或不能验证的元数据都会令匹配失效。显式空目录也需匹配。ZIP 不会解压到磁盘。参见 [ExtractedZIPAnalyzer.swift](../Sources/CleanerCore/ExtractedZIPAnalyzer.swift) 和 [ZIP 格式规范](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT)。

两层分开计量读盘、条目和耗时。ZIP 还限制单包的中央目录和解码预算。达到预算后保留已核验结果，并标记扫描覆盖受限。计时在分块边界检查，适用本地文件的正常读盘行为。

## 选择与执行

页面默认打开「全部大文件」，并使用「按选择」排序，把选中文件及其所在目录排在前面。递归发现的目录树默认展开顶层目录。「重复大文件」分段只显示有重复证据的文件，底栏也只提交该范围内的选择。两个范围均显示建议原因，重复项额外显示保留路径。选中表示可提交清理，仍须点击确认。参见 [DiskSpaceView.swift](../Sources/CleanerApp/DiskSpaceView.swift)、[DiskUsageOutlineView.swift](../Sources/CleanerApp/DiskUsageOutlineView.swift) 和 [AppModel.swift](../Sources/CleanerApp/AppModel.swift)。

满足大文件阈值、通过本地文件检查的 `.dmg`、`.pkg`、`.mpkg`、`.xip`、`.iso` 按格式预选，沿用 [InstallerDiscovery.swift](../Sources/CleanerCore/InstallerDiscovery.swift) 的格式表。受保护、活跃或不可读的文件不预选。已经查实的副本组仍只预选一份，已解压 ZIP 依赖的安装文件也保留。普通 ZIP 不会因为扩展名获得安装包建议。

「设置 → 重复大文件 → 默认勾选大文件中的安装包」默认开启并跨启动保存。设置在下次扫描或刷新大文件时生效，保留当前结果里的勾选。关闭后仍显示安装文件类型，并可手动勾选；同一文件若有重复副本证据，按查重规则预选。

清理计划拒绝同时移走保留件或包含保留件的目录。执行前复验目标及保留路径的快照，变化时跳过。成功处理的建议和受清理影响的旧证据从列表移除。含重复大文件的批次进入手动保留的隔离区，可以在恢复记录中恢复或进一步清理。参见 [LargeFileCleanupProof.swift](../Sources/CleanerCore/LargeFileCleanupProof.swift)、[Planning.swift](../Sources/CleanerCore/Planning.swift) 和 [Execution.swift](../Sources/CleanerCore/Execution.swift)。

## 验收

安装包预选设置实施计划：

- [x] 在设置的大文件区增加持久开关，首次默认开启，下一次扫描或刷新应用。
- [x] 把开关值传到共同的大文件扫描入口。安装包证据和手动选择始终保留，只有安装包规则的自动勾选受影响。
- [x] 用同一组夹具验证开关两侧、重复安装包、已解压 ZIP 和当前手动选择，检查应用重新读取设置。

- `swift test --filter DuplicateLargeFileTests` 验证任意格式精确副本、递归与 Spotlight 结果一致、安装包预选与保留件冲突、同级 ZIP、含小文件和空文件的有效匹配、总大小不足或小成员内容变化时排除、计划保留约束、隔离与恢复。
- `swift run CoreContractChecks` 验证导航、扫描和清理契约。
- `python3 Scripts/check-localizations.py` 检查双语资源。
- `CleanerApp --scan-cleanup-self-check` 验证扫描与选择状态。设置 `SUPERCLEANER_DUPLICATE_FIXTURE` 指向 `Tests/` 中的夹具目录，提供超过 10 MB 的 `a.rip`、`b.data` 相同副本，可与同级文件夹完整匹配的 `packed.zip`，以及比上述选中项大但小于一个未选中文件的 `setup.dmg`。自检验证默认范围、选择排序、安装包预选、重复筛选隔离和保留路径失效。

`0.3.5 (79)` 通过 93 项 Swift 测试、全量核心契约、双语资源和应用包签名验证。签名包通过含 1 字节及空文件成员的真实 ZIP 夹具自检。新包位于 `build/zip-folder-fix/SuperCleaner.app`。

本次更正集中在 [ExtractedZIPAnalyzer.swift](../Sources/CleanerCore/ExtractedZIPAnalyzer.swift) 的清单预筛，改用未压缩文件总大小。[DuplicateLargeFileTests.swift](../Tests/CleanerCoreTests/DuplicateLargeFileTests.swift) 验证小成员允许匹配、同大小小成员内容不同会拒绝、总大小小于 ZIP 会排除。[README.md](../README.md)、[架构](../docs/architecture.md) 和 [开发指南](../docs/development.md) 分别更新使用规则、预筛依据和回归范围，[Version.json](../Version.json) 递增补丁版本。

## 文件改动

| 文件 | 改动原因 |
| --- | --- |
| [SystemScanCoordinator.swift](../Sources/CleanerCore/SystemScanCoordinator.swift) | 索引和递归发现汇入同一核验流程，发布一个模块终态及真实覆盖。 |
| [ReadOnlyInterface.swift](../Sources/CleanerCore/ReadOnlyInterface.swift) | CLI 单模块扫描和桌面入口复用同一个大文件协调器。 |
| [LargeFileContentAnalyzer.swift](../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 按大小分桶并分块比较所有格式，合并两层推荐和保留关系。 |
| [ExtractedZIPAnalyzer.swift](../Sources/CleanerCore/ExtractedZIPAnalyzer.swift) | 有界读取 ZIP 清单和内容，核对同级目录的完整结构和字节。 |
| [CleanerZIP.h](../Sources/CleanerZIP/CleanerZIP.h)、[module.modulemap](../Sources/CleanerZIP/module.modulemap)、[Package.swift](../Package.swift) | 分别声明所用系统 ABI、让 Swift 导入并链接系统库，以及在 CleanerCore 注册构建依赖。 |
| [LargeFileCleanupProof.swift](../Sources/CleanerCore/LargeFileCleanupProof.swift) | 持有待清理目标和保留内容的高精度快照，并验证同批路径冲突。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 原候选保留同一 ID，携带可编码证明和可展示的原因。 |
| [DefaultCleanupPolicy.swift](../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 把具有有效扫描证据的可选项作为重复大文件维度的默认建议。 |
| [Planning.swift](../Sources/CleanerCore/Planning.swift)、[Execution.swift](../Sources/CleanerCore/Execution.swift) | 分别在计划构建和执行边界阻止保留路径被选中，并在移动前复验两端。 |
| [CleanupExecutionCoordinator.swift](../Sources/CleanerCore/CleanupExecutionCoordinator.swift) | 含重复证明的批次保持可恢复，由用户在历史记录里进一步处理。 |
| [CleanupReportReconciliation.swift](../Sources/CleanerCore/CleanupReportReconciliation.swift) | 对已移走或已变化的路径撤销旧证明，保留普通文件清单。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 管理默认勾选、范围选择、失效对账和应用层自检。 |
| [ApplicationScopePicker.swift](../Sources/CleanerApp/ApplicationScopePicker.swift)、[DiskSpaceView.swift](../Sources/CleanerApp/DiskSpaceView.swift) | 抽出共用原生分段控件，在重复页显示推荐原因、保留路径及完整文件范围。 |
| [DashboardView.swift](../Sources/CleanerApp/DashboardView.swift)、[AppNavigationPolicy.swift](../Sources/CleanerCore/AppNavigationPolicy.swift)、[ScanDiscoverySummary.swift](../Sources/CleanerCore/ScanDiscoverySummary.swift) | 统一清理中心、侧栏及发现摘要的重复大文件名称与含义。 |
| [PermissionsView.swift](../Sources/CleanerApp/PermissionsView.swift)、[ScanAccessTracking.swift](../Sources/CleanerApp/ScanAccessTracking.swift) | 说明阈值与内容核验的关系，保留独立于目录权限的预算限制。 |
| [Components.swift](../Sources/CleanerApp/Components.swift) | 更新维度名称和确认指引，一键系统清理容量仅计实际会执行的系统项。 |
| [CleanerApp.swift](../Sources/CleanerApp/CleanerApp.swift) | 通过已有自检入口接收只读夹具，验证应用层选择流程。 |
| [英文资源](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[简中资源](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 同步界面名称、状态、证据和保护提示。 |
| [DuplicateLargeFileTests.swift](../Tests/CleanerCoreTests/DuplicateLargeFileTests.swift)、[AppNavigationContract.swift](../Sources/CoreContractChecks/AppNavigationContract.swift) | 验证两层行为、保留件保护、可恢复执行和导航名称。 |
| [AgentScannerContract.swift](../Sources/CoreContractChecks/AgentScannerContract.swift)、[ReviewRegressionContract.swift](../Sources/CoreContractChecks/ReviewRegressionContract.swift)、[ReadOnlyInterfaceContract.swift](../Sources/CoreContractChecks/ReadOnlyInterfaceContract.swift) | 分别修正共享根所有权、深度检查和包内 CLI 的夹具，使既有门禁覆盖真实目录和祖先身份。 |
| [README.md](../README.md)、[架构](../docs/architecture.md)、[开发指南](../docs/development.md)、[Version.json](../Version.json) | 分别同步使用说明、模块与执行链路、验证方法和本次补丁版本。 |

`0.3.6 (80)` 默认视图和安装包预选的增量审查：

| 文件 | 本次改动和原因 |
| --- | --- |
| [InstallerDiscovery.swift](../Sources/CleanerCore/InstallerDiscovery.swift) | 共享安装文件格式表和证据文案，避免两个扫描模块的识别口径分叉。 |
| [LargeFileContentAnalyzer.swift](../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 查重后检查剩余安装文件的本地身份，确保额外预选不会选中核验所依赖的保留件。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 在原候选上存放建议原因，复用现有预选标记；清除重复证明时同步清除旧原因。 |
| [DefaultCleanupPolicy.swift](../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 用明确的扫描证据决定大文件预选，维持一键系统清理的范围。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 设置默认范围和排序，统一安装包与重复项的预选及刷新对账；自检覆盖排序和筛选。 |
| [DiskUsageOutlineView.swift](../Sources/CleanerApp/DiskUsageOutlineView.swift) | 默认展开递归结果的顶层目录，显示预选原因和保留路径，禁用被阻止的行。 |
| [DiskSpaceView.swift](../Sources/CleanerApp/DiskSpaceView.swift)、[DashboardView.swift](../Sources/CleanerApp/DashboardView.swift) | 在文件页和清理中心说明安装包识别与查重各自的作用。 |
| [SystemScanCoordinator.swift](../Sources/CleanerCore/SystemScanCoordinator.swift)、[英文资源](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[简中资源](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 明确预算只限制重复项推荐，不影响已有文件清单；同步双语文案。 |
| [DuplicateLargeFileTests.swift](../Tests/CleanerCoreTests/DuplicateLargeFileTests.swift) | 验证两种扫描入口的安装包预选一致，保留路径、保护规则和阈值继续生效。 |
| [README.md](../README.md)、[架构](../docs/architecture.md)、[开发指南](../docs/development.md)、本文、[Version.json](../Version.json) | 同步默认行为、识别边界、验收方法、逐文件审查与版本。 |

`0.3.7 (81)` 安装包预选设置的增量审查：

| 文件 | 本次改动和原因 |
| --- | --- |
| [PermissionsView.swift](../Sources/CleanerApp/PermissionsView.swift) | 在大文件阈值旁增加预选开关，说明扫描或刷新后生效。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 保存用户偏好，在三个扫描入口共享的模块启动处传值；刷新时区分默认和手动选择；自检验证持久化和刷新。 |
| [SystemScanCoordinator.swift](../Sources/CleanerCore/SystemScanCoordinator.swift) | 把每次扫描的开关传给分析器，保持其他调用方的默认行为。 |
| [LargeFileContentAnalyzer.swift](../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 仅在标记安装包预选时使用开关，保留查重和安装文件识别。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 将安装包类型证据与默认选择标记分开，关闭预选后仍有可供查看的证据。 |
| [DefaultCleanupPolicy.swift](../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 按扫描结果的预选标记生成默认集合。 |
| [英文资源](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[简中资源](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 增加两种语言的设置名称和生效说明。 |
| [DuplicateLargeFileTests.swift](../Tests/CleanerCoreTests/DuplicateLargeFileTests.swift) | 验证关闭设置后只保留查重预选，普通安装包仍可查看和选择。 |
| [README.md](../README.md)、[架构](../docs/architecture.md)、[开发指南](../docs/development.md)、本文、[Version.json](../Version.json) | 更新设置路径、扫描行为、验收和补丁版本。 |

## 自审与优先级

| 层级 | 建议 | 评分 | 处理 |
| --- | --- | ---: | --- |
| 局部 | 同时验证原副本、ZIP 和保留路径，并覆盖两类建议重叠 | 98 | 已实现并回归验证。 |
| 全局 | 桌面与 CLI 单模块使用同一扫描链路，沿用隔离和历史 | 95 | 已实现。 |
| 局部 | 默认展开递归扫描的顶层目录，并在全部文件视图说明勾选原因 | 92 | 已实现。 |
| 全局 | 合并安装包与查重选择决策，复用同一格式表，并验证生成的默认计划没有保留件冲突 | 98 | 已实现并回归验证。 |
| 局部 | 持久保存设置，并在开关旁说明下次扫描生效 | 95 | 已实现。 |
| 全局 | 把安装包的识别证据与自动勾选分开，并由共享入口处理三个扫描路径 | 98 | 已实现并回归验证。 |
| 局部 | 用真实用户分布测量数 GB 文件的核验时延后调预算 | 81 | 保留现有独立预算，待有代表性样本再评估。 |
| 全局 | 增加跨目录索引、更多归档格式或持久化指纹 | 68 | 先验证当前同级 ZIP 范围的实际覆盖。 |
