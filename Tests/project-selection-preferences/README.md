# 项目筛选与默认勾选设置

本轮逐文件复核如下。工作树还保留先前已授权的累积改动，前序审计见 [上一批记录](../dashboard-sidebar-footer/README.md)，本轮没有回退、提交或推送。

| 文件 | 本轮改动及必要性 |
| --- | --- |
| [ProjectArtifacts.swift](../../Sources/CleanerCore/ProjectArtifacts.swift) | 已确认 Git 跟踪不再单独阻断选择，未知 Git 状态继续拒绝。目录与 DMG 保留跟踪证据和显式选择标记；执行复验采用同一规则。临时 DMG 分析候选保留标记，避免 tracked 测试素材参与自动副本/keeper 配对。 |
| [LargeFileContentAnalyzer.swift](../../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 复用既有手选范围给 tracked 项目 DMG，允许 .build/checkouts 中的文件。保持公共快照的路径、保护、活动、权限、云盘与包边界，普通大文件自动范围不变。 |
| [DefaultCleanupPolicy.swift](../../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 项目预选由统一布尔策略控制，初始关闭；关闭时即使项目手选也不进入首页默认队列。模型仍始终排除。 |
| [ResourceCleanupListPolicy.swift](../../Sources/CleanerCore/ResourceCleanupListPolicy.swift) | 集中提供项目三项/模型四项范围，供界面与回归共享。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 持久化 projects.preselectArtifacts；跟踪自动选择与本报告人工取消，关闭只撤自动项，开关切换保留手选/撤选/主动范围及搜索排序。清空选择统一走项目入口；新模块结果重置其默认策略；即时使首页缓存失效。偏好依赖改为通用名称，新增隔离偏好自检。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 项目移除 Cleanable，使用可见列表位置映射实际范围，防止 enum rawValue 错位；三段缩为 315pt，模型仍为四段 420pt。 |
| [PermissionsView.swift](../../Sources/CleanerApp/PermissionsView.swift) | 项目扫描设置增加含义明确的开关和说明，扫描/执行等忙碌状态禁用。 |
| [ResourceCleanupPresentationFixture.swift](../../Sources/CleanerApp/ResourceCleanupPresentationFixture.swift) | 项目 fixture 的 .build 带显式选择标记，让既有与新页面回归实际覆盖 tracked 选择路径。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 设置开关与说明双语，跟踪证据不再错误宣称永远保护。 |
| [ProjectArtifactContract.swift](../../Sources/CoreContractChecks/ProjectArtifactContract.swift) | Git 跟踪目录契约从 blocked 改为 review/显式选择，其余嵌套库、凭据、活动、预算和隔离恢复契约保留。 |
| [ProjectInstallerTests.swift](../CleanerCoreTests/ProjectInstallerTests.swift) | 重现 .build/checkouts 内两份相同 Git 跟踪 DMG，覆盖手选、执行复验、隔离和恢复，不产生自动副本证明；覆盖 tracked 目录、未知 Git、后增凭据、活动与永久保护。 |
| [DefaultCleanupSelectionTests.swift](../CleanerCoreTests/DefaultCleanupSelectionTests.swift)、[NewCleanupDimensionsTests.swift](../CleanerCoreTests/NewCleanupDimensionsTests.swift) | 原有项目默认队列测试显式开启设置，新测关闭时排除所有项目、开启时含 tracked 且排除受保护/活动/不完整项。 |
| [ResourceCleanupListPolicyTests.swift](../CleanerCoreTests/ResourceCleanupListPolicyTests.swift) | 证明项目三项范围与模型四项范围，保留手选资格及可见项操作覆盖。 |
| [Version.json](../../Version.json) | 正式编译脚本自动分配 0.4.24（138），单独验证/打包不递增。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 更新现行选择规则、默认关闭、Git 手选与保留边界，替换已过时的双页面 Cleanable/项目固定预选说明。 |
| [实施计划](../../doc/project-selection-preferences-plan.md)、[发布记录](../../doc/release-0.4.24.md)、本目录 | 保存计划、红绿灯、逐文件理由、只读复审及构建安装验证证据，便于复现。 |

## 验证

- [红灯](red.log)：修改前隐藏构建目录 Git 跟踪 DMG 无法选择，执行复验拒绝。
- [定向测试](core-targeted.log)：21 项通过；[导航自检](navigation.log)验证默认关闭、启用含 tracked、偏好持久化、即时首页汇总、手选/撤选/Clear/范围保留、渐进发布和新 generation；不执行真实文件操作。
- [独立审查](review.md)：发现的三个入口问题已修正，复审无剩余重要问题。
- [正式构建](package.log)：0.4.24（138），Core 契约和完整 315 项 XCTest 全部通过，1274 条中英消息检查通过，固定证书签名成功。
- [正式包验证](verification.log)：包结构、签名、SDK 27.2 与 macOS 13 最低版本记录一致；项目偏好自检、导航、并行扫描与清理、Trash 等原有回归通过。
- [DMG 打包](dmg.log)、[安装核对](installation.log)、[产物摘要](artifact-check.json)：构建、安装和只读挂载镜像的 App/Helper 版本、严格签名、Automation entitlement 与三个执行文件 SHA-256 一致，已安装到 /Applications/SuperCleaner.app。
- [原生观察](native-observation.md)：开关 off/扫描中禁用、Project 三项范围与初始 All/未勾选、Git 跟踪 DMG 可手选、Selected 显示和首页排除手选均已确认；测试勾选已清空，未实际执行删除。
- [最终审计](final-audit.log)：源码与编译时哈希一致，打包不再递增，HEAD 未变且无暂存内容；已移除本批安装备份。实时其它模块扫描仍在进行，不宣称六模块实时扫描均已结束。

反思与评分：局部将 Git 可手选和默认预选分开 100/100；全局设置、扫描发布、首页队列与执行复验共用策略 100/100；保留本报告人工决定和主动范围 95/100，均已实施。没有新增依赖，Swift 项目不需要 requirements.txt 或 conda。根目录 AGENTS.md 与 .trae/rules/project_rules.md 均不存在，无待更新的 Project workflow 章节。
