# 清理中心资源汇总与项目 DMG

范围：清理中心纳入项目/模型仍勾选的可清理项；移除两页页头按钮；用户确认项目内 DMG 归 Project，其它 DMG 留大文件。源码与依赖不提交、不推送，既有未提交修改保留。Swift 项目，无新增依赖，不创建 requirements.txt；根目录未发现 AGENTS.md 或 .trae/rules/project_rules.md。

## 逐文件复核

| 文件 | 修改与原因 |
| --- | --- |
| [DefaultCleanupPolicy](../../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 六维度集合使用同一计量/计划入口，纳入资源可清理预选，继续排除撤选、活动和不完整项；原始候选先校验证明再合并。 |
| [AppModel](../../Sources/CleanerApp/AppModel.swift) | 首页就绪/根刷新/保护门禁、资源统计、项目 DMG 转入转出时按路径保留选择；目录与子文件的选择联动，避免取消子文件仍被父目录携带；旧按钮处理函数移除。扩展原导航自检。 |
| [ResourceCleanupView](../../Sources/CleanerApp/ResourceCleanupView.swift) | 删除页头重新扫描/选择目录按钮，分组容量按目录操作去重。 |
| [ResourceCleanupPresentationFixture](../../Sources/CleanerApp/ResourceCleanupPresentationFixture.swift) | 只读 DMG/目录夹具覆盖选择迁移与父子选择，无真实清理。 |
| [ProjectArtifacts](../../Sources/CleanerCore/ProjectArtifacts.swift) | 识别工程根及构建目录内 DMG；执行重新检查归属、manifest、身份/路径/活动/最近 Git 仓库跟踪；原目录检查保留。 |
| [ProjectInstallerOwnership](../../Sources/CleanerCore/ProjectInstallerOwnership.swift) | 项目 DMG 从大文件展示候选和树分流，保留原始记录；迁移副本证明并保护保留副本及覆盖它的目录。 |
| [SystemScanReport](../../Sources/CleanerCore/SystemScanReport.swift) | materialize 优先项目 DMG 并保留证明；快照只读复制仍沿用既有候选与索引，不增加清理完成阶段的文件系统读取。 |
| [LargeFileCleanupProof](../../Sources/CleanerCore/LargeFileCleanupProof.swift) | 同样的内容/身份/保留对象证明支持改归项目的 DMG，避免归类绕过证明。 |
| [Scanner](../../Sources/CleanerCore/Scanner.swift) | projectActivePaths 及项目活动判断独立，普通活动路径语义保持。 |
| [CleanupRuntime](../../Sources/CleanerCore/CleanupRuntime.swift) | 构建进程目录进入项目活动集合，具体引用文件仍保持普通活动保护。 |
| [BoundedProcess](../../Sources/CleanerCore/BoundedProcess.swift) | 提取真实文件引用，未知文件类型保持保守，不把 cwd 目录套用所有模块。 |
| [DefaultCleanupSelectionTests](../CleanerCoreTests/DefaultCleanupSelectionTests.swift) | 汇总与计划一致、手动卸载排除、资源活动/保护/不完整排除。 |
| [ProjectInstallerTests](../CleanerCoreTests/ProjectInstallerTests.swift) | 根/构建 DMG、下载分流、依赖/最近嵌套 Git/打开文件保护、两种渐进顺序、副本证明与父目录边界。 |
| [NewCleanupDimensionsTests](../CleanerCoreTests/NewCleanupDimensionsTests.swift) | 更新旧“资源不加入默认队列”断言，保留独立扫描与回执对账。 |
| [Version](../../Version.json) | 编译脚本分配 0.4.15（129）后，为新增嵌套 Git 红灯主动停止；最终重编译自动分配 0.4.16（130），不回滚、不手动 bump。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 同步用户操作入口、默认队列、DMG 归属、活动与证明边界。历史发布记录保留历史含义。 |
| [计划](../../doc/cleanup-center-resource-sync-plan.md)、[发布记录](../../doc/release-0.4.16.md)、本目录 | 记录范围、反思、逐文件理由与实际验证。 |

## 回归与审查

[资源红灯](resource-red.log)和[模型红灯](app-red.log)复现旧排除；[DMG 红灯](installer-red.log)记录新增能力尚未实现。[独立审查修正红灯](proof-red.log)复现证明丢失，[选择迁移红灯](migration-red-2.log)、[父子选择红灯](hierarchy-red.log)、[嵌套 Git 红灯](nested-git-red.log)均实际失败后修复。

独立只读审查指出的 P1 副本证明丢失、P2 转回大文件丢默认均已补回归。实现者另查明父子撤选和嵌套仓库跟踪边界并修复。当前定向与模型最终结果见 [定向回归](final-targeted-green.log)、[模型自检](final-self-check.log)；正式结果见 [完整构建](package.log)、[包验证](verification.log)、[打包](dmg.log)、[安装](installation.log)、[最终审计](final-audit.log)。

局部建议评分：默认集合一致 100、按钮移除 100、DMG 来源分流 99。全局建议评分：保留跨模块证明与选择语义 100、隔离活动目录 99、嵌套仓库复验 100，均实施；无额外范围扩张。构建期间发现新边界即中止，不能将旧版本预先当成已验收结果。

## 最终验收

- 固定证书正式构建通过 310 项 Release 测试、0 失败、核心契约、1271 条双语检查；包内模型/默认计划/保护与并发回执自检通过。
- App、Helper、安装副本与挂载 DMG 均为 0.4.16（130）；严格签名、原有 entitlement 和三个可执行文件哈希一致。[产物信息](artifact-check.json)记录大小与 SHA-256。单独验证/打包未再次递增版本。
- 原生项目页默认 Cleanable、5/37 条目可见，5 项预选约 4.71 GB，含本次 build/SuperCleaner-0.4.16.dmg（298.9 MB）。两资源页无页头按钮；模型页默认 Cleanable、3/4 条目，预选 3 项约 2.08 GB，Ollama 仍保护。
- 取消本次项目 DMG 后，项目页与首页同时变为 4 项约 4.41 GB，全部默认合计由 8 项约 6.79 GB 变为 7 项约 6.49 GB；恢复后均正确恢复。项目页与模型页间导航保留选择。
- 大文件 All 范围搜索本次 DMG 无结果，项目归属无重复展示；下载目录 DMG 保留原功能由真实文件夹具验证。设置显示 0.4.16 / 130。
- 原生验收截至资源模块与大文件完成时，系统、卸载和 Agent 的本次只读全扫描仍在后台运行；本批不据此声称其它模块的真实扫描已经结束。完整模块逻辑以 Release 回归与契约为证据。
- 项目根配置[前](user-config-before.json)/[后](user-config-after.json)指纹一致；没有执行用户文件删除、清空废纸篓、权限或 Helper 注册。自建备份、挂载点及自检夹具已清理，用户选择恢复至初始预选状态。
- 本轮逐文件 git diff 复核正向且必要；当前文档链接与最终 diff 检查见 [审计](final-audit.log)。无未处理的重要审查问题；未提交、未推送。
