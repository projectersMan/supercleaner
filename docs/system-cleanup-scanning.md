# 系统清理：分类、扫描与执行边界

更新日期：2026-11-24。系统清理发现明确的缓存、日志、临时产物和历史残留；应用卸载仍由独立模块负责。

## 分类与默认选择

| 分组 | 必须满足的条件 | 常见内容 | 默认选择 |
|---|---|---|---|
| 推荐清理 | 完整检查、可删除，具备低影响许可或已验证可再生/无引用证明 | 合格日志、本地 GPU/Code 缓存、pip/npm 下载、SwiftPM 仓库、Homebrew 下载、Xcode/Gradle/Go 缓存 | 是；可能重新下载或重建 |
| 深度清理 | 原保留与受保护内容，供进一步逐项复核 | 未识别缓存、卸载应用遗留用户数据、离线/共享内容、聊天文件，以及凭证和无法完整检查的目录 | 否；受保护项不可选择 |

界面只展示推荐清理和深度清理两个可折叠区：推荐展开，深度默认折叠。原 Deep Cleanup 合并到推荐，原 Keep and Protected 合并到深度，不再有第三个区。每组按 System 与具体应用并列展示。受保护项目仍不可选，容量不完整时明确显示未确认。

底层证据仍区分低影响推荐、已验证可再生、需保留和受保护。展示时，前两者聚合为推荐，后两者聚合为深度。低影响要求 `safe` 与明确的 `defaultSelection == true`；可再生要求验证范围与规则匹配的再生/无引用证明。字段缺失、仅有目录名称、`review` 类别或完整遍历都不是推荐依据。合并分组不扩大任何规则的扫描或删除范围。

默认策略为 `.smart`，选择合并后的整个推荐组；既有 `.deep` 批量策略使用同样的已验证集合，不自动选择深度复核中的数据。深度组可选择项需手动确认，清理中心与最终执行计划包含这些明确选择。用户数据不能因未发现对应 App 就自动推荐；敏感内容仍保护，无法确认的历史残留逐项复核。

System 和应用子组的批量选择都不为 `requiresExplicitSelection` 项目授予同意；这类项目必须点击具体条目。活动标记不会让已验证可再生缓存从总计划中静默消失，普通活动文件、模型与项目仍受原有保护。

## 发现与复验

- [静态规则](../Sources/CleanerCore/Resources/base-rules.json) 精确定位已知工具产物；[规则引擎](../Sources/CleanerCore/CleanupRuleEngine.swift) 检查路径、后代、敏感内容、链接、完整性与再生依据。
- [应用专项扫描](../Sources/CleanerCore/ApplicationCleanupScanner.swift) 根据 Bundle ID、容器声明及明确目录叶子发现缓存和日志。网络缓存与本地 GPU/Code 缓存分别声明使用影响；日志只匹配明确扩展名，不把整个 Application Support、Documents 或容器作为普通缓存。
- Chrome 普通缓存与 Service Worker/CacheStorage 分开；离线内容需明确选择。Cookie、密码库、浏览历史、IndexedDB、Local Storage 不因属于浏览器目录而自动可删。
- 微信只发现明确缓存/日志叶子；聊天记录、附件、备份等不作为可默认清理内容。敏感内容或未完整检查会使整个候选受保护。
- [历史残留扫描](../Sources/CleanerCore/HistoricalResidueScanner.swift) 的“未发现所有者”只说明归属状态，不证明文件没有价值；凭证检测与规则引擎共用。
- 静态精确规则及应用专项根优先，通用规则拆分祖先并保留兄弟项，避免重复展示或扩大清理范围。
- 扫描仍是只读发现。执行前重新读取规则、保护清单、身份、归属与需要的引用证明；最终结果区分成功、跳过和失败，不为减少剩余数量而绕过检查。

已验证的可再生运行时缓存沿用既有活动处理能力；不能只凭某个 node/python/swift 进程存在就判定特定下载缓存被使用，也不能把“可再生”解释成所有文件都能绕过保护和完整性复验。

## 废纸篓与其它任务

清空由 Finder 执行，成功需要明确确认为空，随后刷新实际磁盘容量。它与浏览、筛选、选择、只读扫描及模块刷新独立；这些操作不会因为正在清空就禁用整个页面。

重复清空、实际清理、卸载、恢复、维护和更新继续互斥，避免清空时新增的废纸篓内容被同一次永久删除。扫描期间可以发起清空，清空期间也可以开始或继续扫描；取消其中一项不应停止另一项。

## 如何判断“为什么仍有项目”

先检查对应回执，区分未进入所选计划、成功后重新生成、被保护或身份变化而跳过、实际 I/O 失败。不能仅凭下一次扫描仍有目录就推断上一批失败。

回执保存实际尝试的结果；未选择的项目与当时完整扫描快照不在历史中。因此，某路径及其祖先/后代没有回执覆盖记录，只能证明可见历史没有记录处理它，不能反推当时存在、已经勾选或不应清理。

## 验证与来源

- [分类回归](../Tests/CleanerCoreTests/SystemCleanupClassificationRegressionTests.swift) 使用隔离目录覆盖真实 bundled pip/npm/SwiftPM/Homebrew 规则、应用网络/GPU/日志、未知缓存、历史用户数据和凭证保护。
- [总计划回归](../Tests/CleanerAppTests/CleanupCenterPlanTests.swift) 验证合并后的推荐默认包含已验证缓存，取消/重选与最终计划一致；深度复核数据不会自动混入。
- [任务独立性回归](../Tests/CleanerAppTests/TrashTaskIndependenceTests.swift) 和 [废纸篓测试](../Tests/CleanerAppTests/TrashEmptyingTests.swift) 不调用 Finder 删除用户内容。
- [pip 缓存说明](https://pip.pypa.io/en/stable/topics/caching/) 与 [Homebrew 手册](https://docs.brew.sh/Manpage.html) 说明下载缓存的作用；能重新获取并不代表清理没有网络或时间成本。
- 构建与正式验证命令见 [开发指南](development.md)；历史验证事实见 [历史记录](history.md)。
