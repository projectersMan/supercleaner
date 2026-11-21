# 磁盘刷新与系统清理历史恢复

## 结论与历史依据

- `9837f48`（2026-11-12，0.3.30/104）：普通应用缓存与已识别日志具有推荐清理资格，页面按建议清理/保留组织，内层按具体应用归属分组。
- `7e9d39f`（2026-11-13，0.3.35/109）：ApplicationCleanupTarget.rule 和 scan 输出同时改成 `defaultSelection: false`、`requiresExplicitSelection: true`，给全部应用生成数据追加 manual-only 证据。提交说明明确包含“应用生成数据统一默认保留”。这会把缓存/日志移到保留组，并减少默认可清理容量；不是仅修改标签。该提交同时扩展扫描和增加微信手动文件发现，不能整体撤销。
- `2df4845`（0.5.10）：移除激活时容量读取；没有一分钟监控，外部释放磁盘空间后侧栏可长期过期。
- 本轮最初的 0.5.11/156 已安装，但错误地把 System/Applications 放在推荐之前。0.5.12/157、0.5.13/158 中间包构建完成但未安装。只重排界面不能解决推荐规则回退，这一点已纠正。

## 最终改动边界

保留 main 上其它模块和后续的扫描覆盖、零容量过滤、输入法/用户文件保护、完整扫描检查及执行复验。仅恢复普通应用缓存/日志的历史推荐资格；共享缓存、离线内容、微信聊天文件仍然手动选择。其中 Chrome 离线内容保留后来的手动限制，不照搬旧版自动选择行为。

页面复用既有 GuidedCleanupView：建议清理默认展开，建议保留默认折叠；内层直接是 System 或各具体应用，没有 Applications 父层。撤销本轮额外引入的历史 Bundle ID 分组和布局重构，只保留 System 标签和图标。普通日志属于 deepClean，当前统一推荐清理区及默认策略包含该类；没有提高风险等级或伪造容量。

磁盘容量由独立可观察监控对象每 60 秒刷新，启动、激活和清理相关事件也触发。文件系统读取在后台 utility 任务执行，并发请求合并；数值不变不发布，侧栏单独观察，避免触发整个清理列表重算。

## 验证

先修改回归预期，旧实现的 7 个应用生成数据测试出现 7 个断言失败，明确复现普通缓存仍保留和默认容量为零。固定夹具有缓存、日志、离线内容、共享缓存各 7 字节；恢复后应仅选中前两项共 14 字节，另 14 字节仍保留。微信多账号聊天文件、数据库排除、执行要求退出、零字节过滤、分区/沙盒新扫描路径继续检查。

测试与构建记录位于 [Tests/temporary/recommendation-first](../Tests/temporary/recommendation-first)。真实机器容量随应用运行变化，不把跨时间截图的差额当成严格性能或容量基准。未执行用户文件清理。

## 逐文件 diff 审计与必要性

| 文件 | 修改原因 |
| --- | --- |
| [DiskCapacityMonitor.swift](../Sources/CleanerApp/DiskCapacityMonitor.swift) | 独立心跳、请求合并、错误和容量发布，避免全局列表刷新。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 容量入口接入监控，恢复激活刷新，清空完成等待最新容量。 |
| [ContentView.swift](../Sources/CleanerApp/ContentView.swift) | 侧栏单独观察容量。 |
| [GuidedCleanupView.swift](../Sources/CleanerApp/GuidedCleanupView.swift) | 撤回本轮结构改造，复用历史两级布局，仅区分 System 图标。 |
| [SystemCleanupApplicationGroup.swift](../Sources/CleanerCore/SystemCleanupApplicationGroup.swift) | 仅将混合兜底组名称改为 System，保持原归属和容量排序。 |
| [ApplicationCleanupScanner.swift](../Sources/CleanerCore/ApplicationCleanupScanner.swift) | 撤回统一 manual-only，恢复普通缓存/日志；仅手动数据继续保留，传递引擎检查结果。 |
| [英文资源](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 同步 System 名称。 |
| [CoreReadOnlyContract.swift](../Sources/CoreContractChecks/CoreReadOnlyContract.swift) | 失败信息同步组名。 |
| [SystemCleanupContract.swift](../Sources/CoreContractChecks/SystemCleanupContract.swift) | 缓存/日志恢复推荐断言；离线/聊天文件/保护契约不放宽。 |
| [Package.swift](../Package.swift) | 注册真实 AppModel 容量回归测试，无新包依赖。 |
| [DiskCapacityRefreshTests.swift](../Tests/CleanerAppTests/DiskCapacityRefreshTests.swift) | 六项行为回归覆盖计时、激活、合并、同值无通知、失败恢复和生命周期。 |
| [SystemCleanupApplicationGroupTests.swift](../Tests/CleanerCoreTests/SystemCleanupApplicationGroupTests.swift) | 两项验证 System 标签和同级应用分组无重复/丢失、选择不变。 |
| [ApplicationGeneratedDataTests.swift](../Tests/CleanerCoreTests/ApplicationGeneratedDataTests.swift) | 普通缓存恢复及混合数据容量回归；继续覆盖微信保护和扩展发现。 |
| [Version.json](../Version.json) | 构建脚本自动分配版本。 |
| [README.md](../README.md) | 同步使用方式、当前版本和恢复行为。 |
| [doc/architecture.md](architecture.md)、[docs/architecture.md](../docs/architecture.md) | 同步独立容量状态和历史推荐数据流。 |
| [doc/development.md](development.md)、[docs/development.md](../docs/development.md) | 同步刷新边界和回归验证要求。 |
| release-0.5.10.md、release-0.5.11.md、release-0.5.15.md | 保留已交付/未安装历史并指向最终恢复记录。 |
| 本文与最终版本说明 | 保存可复核的提交依据、验证、交付和修改原因。 |

## 自我复核与下一步评分

- 局部：以 0.3.30 恢复普通缓存/日志，保留实际手动边界（100/100），已实施。
- 局部：撤回新层级和额外历史归属规则，复用既有两级界面（100/100），已实施。
- 全局：用混合夹具同时锁定推荐容量与保留项，防止其它功能开发再次改变系统清理推荐（97/100），已实施。
- 全局：容量心跳隔离 UI 状态并合并读取（98/100），已实施。

没有为增加容量而放宽用户数据保护，也不做全仓库历史回退。没有新增依赖，无需改 requirements.txt；项目为 Swift，无 Python 运行环境变更。未找到 .trae/rules/project_rules.md。未提交或推送。

完整构建期间，0.5.14 在旧 Chrome 全手动契约处停止；同步为普通缓存推荐、离线继续手动后重新完整构建 0.5.15/160，未跳过检查。0.5.14 未打包或安装，版本号依构建脚本继续递增。

0.5.15/160 完整交付检查：351 项 Release 测试、CoreContractChecks、1272 条双语校验及 verify-app.sh 全部通过。安装副本逐文件 SHA-256 与符号链接核对一致，签名身份与原安装相同；已打开并开始只读扫描。临时旧应用备份已在验证启动成功后删除。日志见 history-final-package.log、history-verification.log。

原生验收边界：0.5.15 已在固定路径启动，并停留 System Cleanup。交还时本机只读扫描仍在进行，故不宣称已验证真实结果分组或增加的 GB 数。侧栏多次观测到容量变化，页面切换正常；只读进程采样显示 CleanupRuleEngine 正在逐文件检查。扫描采样保存在 Tests/temporary/recommendation-first/scan-sample.txt，不属于性能回归基准。

## 分组标题更名（安装 0.5.15 后）

按用户要求，仅把 System Cleanup 第二个分组的标题从 Recommended to keep 改成 Deep Clean Up，中文为深度清理。GuidedCleanupView 只更换该处本地化键；中英文资源各增加一个键，保留原建议保留键供候选徽标使用，避免影响其它界面。候选集合、数量、容量、默认折叠、勾选、说明和清理规则均保持。

逐文件复核：GuidedCleanupView.swift 只改标题；两份 Localizable.strings 提供独立标题翻译；README.md、doc/architecture.md、docs/architecture.md 同步使用说明；doc/development.md、docs/development.md 明确仅更名；本文记录边界。局部建议：独立标题键避免连带改候选徽标（100/100），已实施；全局建议：复用现有分类与选择规则，不将标题映射为 deepClean 策略（100/100），已实施。无新依赖或测试夹具；仅运行现有双语检查和 diff 检查。更名编码阶段未构建；随后按用户要求完成 0.5.16 构建安装，见下文。

## 更名版本构建安装

0.5.16/161 已替换并打开。351 项 Release 测试、核心契约、1273 条双语检查和应用打包自检通过；包内标题、安装文件摘要和符号链接、原签名身份均已核对。旧应用备份已清理。新版停留 System Cleanup 并运行只读扫描，未执行清理；分组将在扫描完成后显示。首次构建权限自动审核超时，按提示重试一次后成功，无未解决的权限阻塞。版本和当前交付文档同步，功能源码未再变化。详见 [0.5.16](release-0.5.16.md)。

## 分类标题英文风格统一（0.5.16 安装后）

两类统一使用名词 Cleanup 和标题式大小写：Recommended Cleanup、Deep Cleanup。仅修改英文 Localizable.strings 的两条译文；中文、分组、说明、默认折叠及选择行为均不变。建议清理键也用于 Agent 页分类标题，因此同名分类同步大小写，不引入重复本地化键。README.md、doc/architecture.md、docs/architecture.md、doc/development.md、docs/development.md 同步当前标题；历史发布记录保留实际发布文字。

逐文件 diff 复核：英文资源只统一两处标题；五份现行说明仅同步命名；本文记录改动边界。局部建议：分类名统一名词和大小写（100/100），已实施；全局建议：同名分类共用译文且保持行为逻辑不变（95/100），已实施。现有双语校验和 diff 检查通过，无新依赖或测试。本次仅修改代码与文档，未重新构建安装。

## 统一英文标题版本安装

随后按用户要求构建、替换并打开 0.5.17/162。351 项 Release 测试、核心契约、1273 条双语校验和打包自检通过；安装文件摘要、链接、原签名身份以及 Recommended Cleanup / Deep Cleanup 两处标题均已核对。应用停留系统清理页运行只读扫描，没有执行用户文件清理；旧应用临时备份已删除。版本、README 和 doc/docs 现行架构/开发指南同步更新，具体逐文件复核及建议评分见 [0.5.17 说明](release-0.5.17.md)。
