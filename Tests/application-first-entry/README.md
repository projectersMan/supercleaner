# 应用卸载首次进入与统一清空弹窗

本批保留先前未提交工作，只编译打包供测试；前序审计见 [0.4.25 记录](../trash-exit-reuse/README.md)。

## 性能证据

原 `--application-responsiveness-self-check` 在取全量计划后才计时，热缓存约 0.015 秒，没有覆盖首次进入。新增真实 AppModel 冷入口基准，114 个应用、4560 个关联项，包含列表、底栏汇总及首屏 20 行数据读取。

- [冷入口红灯](baseline-cold.log)：0.4916 秒，其中汇总 0.4907 秒，过滤排序约 0.00074 秒。150 毫秒预算明确失败。
- [主线程采样](baseline.sample)：汇总栈 210 次中 207 次落在 ProtectionPolicy.applying，重复解析同一组保护根。带采样运行约 0.99 秒有采样开销，不作为无采样性能基线。
- [图标独立测量](baseline-icons.log)：16 个真实安装应用的首次图标约 0.084 秒、重复约 0.00011 秒。不是本次主要瓶颈，保留原图标归属与缓存。
- [第一步测量](optimized.log)与 [第二次](optimized-2.log)、[第三次](optimized-3.log)：0.0259 / 0.0238 / 0.0219 秒，中位约 0.024 秒。与未采样基线比较，模型首屏数据准备减少约 95%。这不是整个窗口绘制或鼠标响应的端到端时间。
- 中间仅批量复用保护根后约 0.1166 秒；继续消除行读取、空汇总和无选择运行刷新触发全表计划后得到上述结果。没有把工作提前到扫描末尾，也没有用延迟掩盖耗时。

## 逐文件复核

| 文件 | 改动及必要性 |
| --- | --- |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 行级分析仅调用当前应用的 checkedUninstallPlan，与全量计划共用现有按 plan.id 的保护缓存；删除不再需要的路径到计划缓存。空文件及 receipt 选择汇总直接零，无选择运行状态刷新与按选择排序不生成全表计划。增加冷缓存首次进入预算；既有报告、保护、运行状态变更与选择回归保持。 |
| [ProtectionPolicy.swift](../../Sources/CleanerCore/ProtectionPolicy.swift) | 新增批量应用入口，每批解析保护根一次，每个候选仍解析当前物理路径。公开 validate 和下一批重新解析，父子重叠、字面/历史/当前物理路径及不可用策略继续拒绝。没有跨操作永久缓存保护路径。 |
| [ProtectionPolicyBatchTests.swift](../CleanerCoreTests/ProtectionPolicyBatchTests.swift) | 对照批量与逐项结果，覆盖父目录、后代、内置保护、符号链接目标变化和不可用策略。 |
| [Controller](../../Sources/CleanerApp/TrashReminderController.swift)、[Observer](../../Sources/CleanerApp/TrashReminderWindowObserver.swift)、[CleanerApp](../../Sources/CleanerApp/CleanerApp.swift)、[TrashEmptyingCheck](../../Sources/CleanerApp/TrashEmptyingCheck.swift) | 按用户补充要求删除来源上下文、跳过和额外选项。首页与关闭最终调用 requestEmptyTrash，完全共用一个两按钮确认；保留等待容量、成功后免重复、取消/失败不免提醒。详细说明见 [独立子任务审计](../exact-trash-dialog/README.md)。 |
| [中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings)、[英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 移除四条已无 UI 使用的关闭/跳过/抑制文案；保留同一永久删除警告和 Cancel / Empty Trash。 |
| [Version.json](../../Version.json) | 正式脚本自动分配 0.4.26（140）；单独验证、镜像与安装不再递增。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 说明行级准备、冷缓存验收、安全检查边界，并更新完全相同的确认及取消语义，消除上一轮额外选项的过时说明。 |
| [性能计划](../../doc/application-first-entry-plan.md)、[弹窗计划](../../doc/exact-trash-dialog-plan.md)、[历史退出计划](../../doc/trash-exit-reuse-plan.md)、[发布记录](../../doc/release-0.4.26.md)、本目录 | 保存红绿灯、采样、范围与必要性，历史方案标明已被统一两按钮确认取代。 |

## 验证

- [定向测试](targeted.log)：两项批量保护回归通过；[导航](navigation.log)、[垃圾桶注入回归](trash-regression.log)通过。
- [真实红色 close 隔离检查](../exact-trash-dialog/native.log)五项通过：同一 factory、两按钮、无新增选项、无真实 Finder 执行、原 delegate/model 保留。首个夹具把默认按钮快捷键恒定当作 Escape 的断言已修正，失败日志保留。
- 独立只读复核未发现重要问题，检查保护等价、缓存失效、运行状态、receipt 选择、同一清空入口、退出等待与失败路径；未代替主任务运行测试。
- [正式构建](package.log)通过 317 项 XCTest、Core 契约及 1266 条中英文本检查；[包验证](verification.log)的冷入口约 0.0178 秒，新旧卸载选择、运行状态、保护更新、清空取消/失败与等待回归均通过。
- [DMG](dmg.log)、[安装核对](installation.log)、[产物摘要](artifact-check.json)确认构建、安装和只读挂载镜像的 App/Helper 版本、严格签名、Automation entitlement 与三个执行文件一致，已更新 /Applications/SuperCleaner.app 为 0.4.26（140）。
- 新版本原生首页显示与截图相同的永久删除警告，仅 Empty Trash / Cancel；只点 Cancel，按钮恢复可用，没有执行真实清空。安装前界面控制被持续操作拦截，经用户回复“已退出”并确认进程退出后才替换应用。
- [最终审计](final-audit.log)核对源码哈希、版本及空暂存区。移除本批安装备份、隔离原生夹具 App 和图标计时二进制；保留复现脚本和日志。新安装会话未进行真实文件清理或重新完整扫描，不把模型基准称为端到端实测。

建议评分：局部冷入口基准和消除空汇总全表准备 100/100；全局保护批内复用、行与全量共用缓存且保持失效 98/100；直接复用清空函数而非维护来源变体 100/100，均已实施。无新依赖，主体 Swift 无 requirements.txt/conda 变动；根 AGENTS.md、CONTEXT.md 和 .trae/rules/project_rules.md 不存在，无 Project workflow 可更新。素材只存 Tests，未提交推送。
