# 清理中心选择与累计验证

用户澄清后的验收口径：六个维度行的“本次已清理”数量/容量之和等于右上角总计；当前手动选择单独显示，不计入已清理。详情页模型数、卸载安装凭据数及推荐执行范围保持原有规则。

## 验证结果

- `swift test`：357 个 Core 测试 + 26 个 App 测试全部通过；应用界面同时编译通过，见 [完整日志](full-suite.log)。
- 新增 1 个 Core 回归、4 个 App 回归，覆盖六维归属、历史残留、成功实际容量与预估不同、零字节成功、失败/取消、重复回执、重试、模型/应用手动选择、大文件推荐/手动混合、切换过滤与页面、清空选择、重新扫描保留累计。
- 新接口实现前，测试因缺少分维度累计和首页选择汇总接口失败；见 [累计失败记录](red.log)、[选择失败记录](red-selection.log)。
- `CleanerApp --navigation-presentation-self-check` 通过，包含 20,000 个 Agent 资源和 5,000 个清理项的缓存回归；见 [导航日志](navigation.log)。
- `CleanerApp --cleanup-completion-self-check` 通过：25,000 项中对账 85 个结果耗时约 274 ms，小于既有 400 ms 上限；见 [完成日志](completion.log)。
- `python3 Scripts/check-localizations.py`：1300 条双语资源、源码引用与占位符检查通过；`git diff --check` 通过。
- 源码验证后已按用户要求随 [0.5.30（175）](../../doc/release-0.5.30.md) 打包并安装，见 [交付验证](../release-0.5.30/README.md)。未提交代码，未执行真实用户文件清理。编译中出现的 `DiskCapacityRefreshTests.swift` 弱变量提示为已有测试代码提示，与本次修改无关。

## 逐文件差异审阅

本次开始时已有大量未提交变更；下表仅列本次新增差异，原有变更保留。

| 文件 | 修改与必要性 |
| --- | --- |
| [CleanupSessionSummary.swift](../../Sources/CleanerCore/CleanupSessionSummary.swift) | 按候选归属同时累加模块与总计，复用成功过滤和回执去重，保证严格可加和。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 为现有选择缓存增加显式页面参数，避免首页读取到空选择；推荐批量清理也走统一完成入口。已有报告安装、完成入口设为模块内可测试，回归直接覆盖实际对账链路。 |
| [CleanupCenterSelectionSummary.swift](../../Sources/CleanerApp/CleanupCenterSelectionSummary.swift) | 从现有选择生成推荐/手动/混合文案，应用复用卸载摘要、模型沿用详情页选择单位，不维护第二套选择状态。 |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 展示当前选择，并独立显示该维度会话累计；扫描中也保留累计，已完成后再次选择不会覆盖累计。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 添加手动已选、当前已选、本次已清理三条英文。 |
| [中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 添加上述三条中文并保持占位符一致。 |
| [CleanupRefreshContract.swift](../../Sources/CoreContractChecks/CleanupRefreshContract.swift) | 调用累计接口时明确传入执行候选，保留来源缺失不计已清理的契约。 |
| [CleanupSessionSummaryContract.swift](../../Sources/CoreContractChecks/CleanupSessionSummaryContract.swift) | 将原有契约迁移到带维度归属的接口，不保留旧计量入口。 |
| [SessionCleanupMetricTests.swift](../CleanerCoreTests/SessionCleanupMetricTests.swift) | 验证分维度和总计精确对齐，实际回执字节优先于候选预估。 |
| [DashboardModuleSummaryTests.swift](../CleanerAppTests/DashboardModuleSummaryTests.swift) | 验证实际 AppModel 的导航、选择、回执对账、重复处理和重扫行为。 |
| [README.md](../../README.md) | 更新使用者可见的选择/清理状态说明并替换过时描述。 |
| [doc/architecture.md](../../doc/architecture.md) | 记录同源累计、归属和会话生命周期。 |
| [doc/development.md](../../doc/development.md) | 记录统一完成入口和回归约束。 |
| [docs/architecture.md](../../docs/architecture.md) | 同步旧目录中仍在引用的首页说明，避免与现行行为矛盾。 |
| [docs/development.md](../../docs/development.md) | 同步旧目录的统计约束并指向现行文档。 |
| [实施计划](../../doc/dashboard-module-metrics-plan.md) | 记录用户澄清、实施边界及完成情况。 |
| 本目录日志与说明 | 保存复现和验证证据；无用基线备份已删除。 |

## 反思与建议评分

最初把问题扩大到统一模型、凭据与结果弹窗的计数单位，不符合用户随后澄清的目标，已经撤销该方向的测试和计划。最终只统一清理中心各行与全局总计，避免无关行为变更。

- 局部：显式按目标页面读取已有选择，100/100，已实施。
- 全局：所有清理入口共用一份按回执去重的模块/全局累计，98/100，已实施。
- 无其它必要的后续代码扩展。无新增依赖，不创建 Swift 项目不需要的 requirements.txt。
