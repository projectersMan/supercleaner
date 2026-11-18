# 清理中心全部默认项验证

本批基于 0.4.6（120）：首页底栏由系统专用队列扩展为所有仍勾选的系统推荐、大文件预选及 Agent 自动预选；模块行仅显示非零默认容量和可执行数量。覆盖说明及安全卡移到标题下、扫描行上方；扫描按钮加大并与标题文字左对齐，废纸篓按钮加大靠右，三个区域保持无容器底色/外框。

## 逐文件审计

| 文件 | 必要修改与原因 |
| --- | --- |
| [DefaultCleanupPolicy.swift](../../Sources/CleanerCore/DefaultCleanupPolicy.swift) | 增加带当前选择/自动 Agent IDs 的策略入口；统一全局去重后的模块统计；计划入口保留原候选供安全校验。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 选中与自动预选变动撤销默认缓存；统一就绪/保护/失败过滤、模块摘要及跨模块执行；执行与回执按最终计划计量，计划拒绝原因显示在底栏，重试时清除旧失败状态。现有导航自检覆盖真实状态门禁，原性能夹具显式选择系统项以符合新语义。 |
| [CleanupActionBars.swift](../../Sources/CleanerApp/CleanupActionBars.swift) | 底栏使用全部默认候选及总容量/数量，修改按钮、等待态与可访问性说明，清楚说明人工选择在模块页确认。 |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 移动说明与安全卡、增大/对齐两按钮、添加非零默认统计；保留六行导航和无滚动布局。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 为新增状态和默认统计增加成对文案。 |
| [DefaultCleanupSelectionTests.swift](../CleanerCoreTests/DefaultCleanupSelectionTests.swift) | 5 项行为测试覆盖手动排除、取消勾选、活动/阻止项、父子和跨模块重叠，以及真实副本证明遮蔽。临时文件全部在本目录并自动清除。 |
| [Version.json](../../Version.json) | 每批只递增一次至 0.4.7（121），App/Helper 一致。 |
| [README.md](../../README.md) | 更新使用布局、全部默认清理的边界和实际交付入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 更新页面结构、默认选择来源与先验证再合并的执行链。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md) | 记录选择缓存失效、零值隐藏、手动边界及真实模型回归要求。 |
| [发布检查表](../../docs/production-release-checklist.md) | 补充全部默认清理和副本证明的发布验收项。 |
| [实施计划](../../doc/dashboard-all-default-plan.md)、[发布记录](../../doc/release-0.4.7.md)与本记录 | 保存需求、步骤、评分和实际验证结果，避免把旧未提交批次当成本批新增内容。 |

## 测试与审查

[最初 RED](red.log)确认缺失跨模块选择入口；[模型 RED](model-red.log)复现旧入口遗漏 Agent 自动项；[重叠 RED](overlap-red.log)复现分模块容量/数量与全局去重不一致。修复后 [5 项专项测试](green.log)通过。

独立审查发现 P1：系统安装包同路径别名或父目录合并后可能遮蔽大文件的保留副本证明。真实同内容 DMG 分析得到的证明同时复现两种情况，[证明 RED](proof-red.log)均为“应拒绝但未拒绝”；改为完整候选先交给 PlanBuilder 后通过。最终执行和回执来自 plan.selectedItems，未放松默认规则。同时 [异步预选 RED](agent-pending-red.log)确认重算期间的旧 Agent 父目录仍可能被执行；现在重算/展示准备期间暂不暴露 Agent 默认项，系统等其他就绪模块仍可独立清理。[模型 GREEN](model-green.log)覆盖该门禁。无遗留审查问题。

局部建议统一统计与执行 100、头部布局 96；全局建议复用安全执行与保持人工选择边界 100，均已实施。项目为 Swift，无新增依赖，不创建 requirements.txt。根目录无 AGENTS.md 或 .trae/rules/project_rules.md。保留既有六维度实现及研究材料，不提交或推送。

## 最终交付

- [固定证书构建](package.log)通过，完整 Release 测试 305 项、0 失败；核心契约和 1259 条双语资源检查通过。
- [完整包验证](verification.log)通过，包含实际 AppModel 跨模块、异步预选、缓存、扫描和保护门禁；清空编排仍只使用假执行器。[DMG 挂载及签名检查](dmg.log)通过。
- [安装核对](installation.log)确认 App/Helper 均为 0.4.7（121），严格签名、Automation entitlement 和三个可执行文件与构建一致，最终可执行文件晚于本批生产源码。
- 原生英语界面确认覆盖说明/安全卡位于扫描行上方，扫描按钮与标题文字左对齐且更大，清空按钮加大靠右，六行与底栏单页完整可见。只读扫描中系统默认 319 项、11.85 GB 与底栏一致；其余无默认项或手动维度不显示零统计，尚在扫描的 Agent 不暴露旧默认项。Agent 单独有默认项和大文件的汇总由专项测试与模型自检覆盖。
- 实机核验只触发只读扫描；观察渐进就绪结果后正常退出，最终包更新后重开空闲首页。未执行清理、清空废纸篓、授予 Automation 权限或注册 Helper。原应用数据和偏好保留。
- 已逐文件审计并清理旧安装备份及包自检测试主目录；见 [最终审计](final-audit.log)。未提交或推送。
