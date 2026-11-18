# 项目 DMG 发现、模型手选与标题栏跟踪

## 本轮范围与逐文件复核

| 文件 | 修改及必要性 |
| --- | --- |
| [ProjectArtifacts](../../Sources/CleanerCore/ProjectArtifacts.swift) | 共用用户根范围和 manifest 归属识别；项目独立核验 DMG 副本并保护保留文件/覆盖目录，不再等待大文件模块提供证明。 |
| [SystemScanCoordinator](../../Sources/CleanerCore/SystemScanCoordinator.swift) | 大文件结果发布前排除项目 DMG，清单和容量树同时过滤，消除先显示后消失。 |
| [ProjectInstallerOwnership](../../Sources/CleanerCore/ProjectInstallerOwnership.swift) | 复用容量树过滤，同时接受项目自己产生的证明并兼容当前扫描中既有证明约束。 |
| [LargeFileContentAnalyzer](../../Sources/CleanerCore/LargeFileContentAnalyzer.swift) | 安装包查重采用 installer 路径范围，code + Package.swift 工程内的相同 DMG 也能保留副本。 |
| [DefaultCleanupPolicy](../../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 模型始终排除默认队列，用户手选也不进入首页全部默认计划。 |
| [AppModel](../../Sources/CleanerApp/AppModel.swift) | 模型仅保留 Cleanable/All 初始范围，不预选；项目仍预选。补首次/渐进/刷新/人工选择保留与模型本页可执行的回归，首页不计模型。 |
| [ResourceCleanupView](../../Sources/CleanerApp/ResourceCleanupView.swift) | 模型页头改为明确手动选择，不再声称预选。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 同一消息配对更新，保持分类、安全提醒与占位符一致。 |
| [ContentView](../../Sources/CleanerApp/ContentView.swift)、删除 SidebarToolbarAlignment.swift | 隔离原生分栏验证后，移除透明标题栏桥接和隐藏工具栏背景，结合正确的链接 SDK 交还系统管理连续边界；无效的重绑与全屏偏好均回退。 |
| [ProjectInstallerTests](../CleanerCoreTests/ProjectInstallerTests.swift) | 发布前排除、用户自定义/空根、普通下载保留、项目独立副本核验；保留活动/Git/父目录/渐进顺序边界。 |
| [DuplicateLargeFileTests](../CleanerCoreTests/DuplicateLargeFileTests.swift) | 原项目 DMG 在大文件预选断言改为项目独立发现，保留普通文件手选与下载安装包逻辑。 |
| [DefaultCleanupSelectionTests](../CleanerCoreTests/DefaultCleanupSelectionTests.swift)、[NewCleanupDimensionsTests](../CleanerCoreTests/NewCleanupDimensionsTests.swift) | 模型分类仍有可选对象，但无默认计划；项目与其它既有默认维度继续工作。 |
| [build-app.sh](../../Scripts/build-app.sh)、[verify-app.sh](../../Scripts/verify-app.sh) | 从 SDKROOT 读取实际 SDK，从 AppInfo 读取最低系统并独立链接；记录 DTSDKName，验证与 Mach-O 一致，避免错误兼容样式。 |
| [Version](../../Version.json) | 由编译脚本从 0.4.16（130）分配中间验证包 0.4.17（131），全屏复核后依次自动递增至 0.4.18（132）、0.4.19（133）、0.4.20（134），不手动 bump。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 同步项目发现阶段归属、模型分类与手动决策边界、标题栏动态对齐、版本与验收要求；历史发布记录保留历史含义。 |
| [计划](../../doc/project-installer-discovery-plan.md)、[发布记录](../../doc/release-0.4.20.md)、本目录 | 记录需求变化、审查修正、逐文件理由及真实验证证据。 |

Cleanable 仅表示路径、权限、活动、内容检查允许选择，不能判断模型是否还需要。模型首次/重扫都不预选，手选内容从本页确认；无关发布及导航不会覆盖人工选择。清理中心全部默认队列不接受模型。

## 回归与审查

[发现阶段红灯](red.log)复现项目 DMG 先被大文件发布；[模型默认红灯](models-manual-red.log)及[模型页红灯](models-app-red.log)复现原自动选择。独立只读审查指出普通 code 工程副本未进入核验，补充 [普通工程副本红灯](project-copy-red.log)后修正 installer 快照范围。[定向回归](final-targeted.log)与[应用模型自检](final-app.log)均通过；[双语检查](localizations.log)通过。

[正式构建](package.log)、[包验证](verification.log)、[DMG](dmg.log)、[安装核对](installation.log)、[最终审计](final-audit.log)记录最终验收，全部通过。

局部建议评分：发现阶段归属 100、模型完全手选 100、全屏工具栏布局 98。全局建议评分：项目独立证明 100、分类与决策分离 100、统一原生窗口布局 99，均实施，无额外功能扩张。

Swift 项目，无新增依赖，不创建 requirements.txt；根目录 AGENTS.md 与 .trae/rules/project_rules.md 均不存在。保留所有前序未提交修改，不提交、不推送。验证不删除用户文件，不清空废纸篓，不更改权限或 Helper 注册。

中间包 0.4.17 的模型手选、项目归属已原生验证，但全屏浮动工具栏仍有约 3pt 边缘错位；相关构建/包/镜像/安装日志以 -0.4.17 后缀保留。重绑分隔符和 0.4.18 的全屏可见性偏好均实测无效，已完全回退；原生隔离分栏边界连续，正式 App 改回系统布局仍复现；定位到 SwiftPM 正式链接记录 sdk 13.0，与隔离窗口实际 sdk 27.2 不同。用户确认修正 SDK 记录后补充构建和校验，最终验收以下方结果为准。

## 最终验收：0.4.20（134）

- 正式脚本自动分配版本；311 项 Release 测试零失败，Core 契约及应用包各项自检通过；中英 1271 条消息配对通过。
- [SDK 旧包红灯](sdk-metadata-red.log)确认原包无 SDK 元数据；[旧包 Mach-O](packaged-sdk.log)记录 sdk 13.0，而[隔离窗口](probe-sdk.log)为 27.2。用户确认修正后，[包验证](verification.log)确认 SDK 27.2、最低系统 13.0 和包元数据一致。
- [安装核对](installation.log)确认构建、安装和只读挂载镜像的 App/Helper 版本、严格签名、Automation entitlement 与三个可执行文件哈希一致；[产物摘要](artifact-check.json)记录 DMG SHA-256。
- 正式 App 的普通窗口、全屏工具栏显示时及侧栏收放后，顶部和内容分栏边界均连续；最后恢复普通窗口。未实测其它 macOS 版本，不将最低版本声明当作跨系统验收。
- 原生扫描开始约 4 秒，大文件先完成而项目仍扫描时无临时项目 DMG Cleanup；模型完成后也不产生首页默认数。0.4.19 同代码实测项目完成后独立显示 7 项约 5.31 GB，手选 whisper 4.6 MB 只改变模型页，首页仍只计项目，导航保留手选；随后取消。
- 最终 0.4.20 新扫描的模型页默认 Cleanable（3 / 4 项），全选、组和三项模型复选框全部为 0，底部 No cleanup items selected，Confirm Deletion 禁用；页头明确手动选择，All / Protected / Selected 分类保留。最终停留此页，不执行清理；其它真实扫描模块未作为本轮完成声明。
- [最终审计](final-audit.log)确认版本打包不重复递增、文档链接和 diff 检查通过，真实项目扫描配置与验证前一致；只删除本轮生成的旧中间镜像、验证 App 和备份，不删除用户素材。

反思：前三次将问题归为视图布局，遗漏了正式 SwiftPM 链接 SDK 与隔离窗口不同这一构建边界；它们均未通过全屏验证，已回退。最终从实际二进制证据定位并修正 SDK 记录，视图仅保留原生布局。发现阶段归属、独立副本约束、模型分类与人工决策分离、构建元数据门禁等评分均不低于 98，已实施；没有扩张到其它功能。
