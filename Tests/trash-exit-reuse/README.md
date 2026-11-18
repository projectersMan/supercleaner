# 关闭与退出复用 Empty Trash

本轮保留先前未提交改动；前批逐文件审计见 [项目选择设置记录](../project-selection-preferences/README.md)。本批仅编译打包，不暂存、提交或推送。

| 文件 | 本轮改动与必要性 |
| --- | --- |
| [TrashReminderController.swift](../../Sources/CleanerApp/TrashReminderController.swift) | 首页/关闭/退出传递上下文到同一永久删除确认与执行入口，返回可等待结果；保留明确跳过和不再提醒，退出另可取消。成功才确认捕获的会话容量，失败沿原错误路径；删除 NSWorkspace.open(.Trash) 分支，避免两套处理或重复确认。 |
| [CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 退出代理以 terminateLater 等待公共任务，结果为成功/明确跳过才 reply true，失败/取消 reply false；同一待处理退出只使用一个任务。可注入控制器供隔离测试，保留默认构造与更新退出门禁。 |
| [TrashReminderWindowObserver.swift](../../Sources/CleanerApp/TrashReminderWindowObserver.swift) | 主窗口关闭传入同一个 AppModel，复用公共清空入口，仍只观察该窗口 willClose，不替换 SwiftUI delegate。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | finishTrashEmptying 增加等待新容量读取，避免退出先于刷新；本轮仅改这一行，前序资源选择等变更保持。 |
| [TrashEmptyingCheck.swift](../../Sources/CleanerApp/TrashEmptyingCheck.swift) | 既有注入自检增加三上下文、重复退出、reply、取消/跳过/抑制、新容量挂起与关闭后退出不重复提醒；从不发送 Finder 命令。 |
| [中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings)、[英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 删除废弃 Open Trash 等五条消息，增加 Cancel Quit；共享原有永久删除警告。 |
| [Version.json](../../Version.json) | 正式编译脚本自动递增为 0.4.25（139），验证和 DMG 打包不再递增。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 同步直接清空、退出等待、确认/失败语义及容量刷新完成边界；修正 README 遗留的项目 Git 跟踪一概保护说明，使其符合上一批已实现规则。 |
| [原关闭计划](../../doc/trash-close-reminder-plan.md)、[本批计划](../../doc/trash-exit-reuse-plan.md)、[发布记录](../../doc/release-0.4.25.md)、本目录 | 历史初始方案标明已替代，记录逐文件理由、失败/成功验证、独立复审与产物证据。 |

## 验证

- [初始接口缺失构建](red-api.log)记录旧控制器缺少可等待的关闭/退出接口，属于编译失败，不称为运行时行为红灯。
- [运行时红灯](red-behavior.log)：临时将退出返回值恢复 terminateNow，自检明确失败“quit must wait”；随后恢复源文件并重建，[定向绿灯](targeted.log)通过。
- 定向绿灯覆盖成功、超时、取消、权限拒绝、未确认空状态；重复调用、用户新清理量、原偏好保留；退出成功/失败 reply；新容量读挂起期间不能退出或释放 gate；关闭窗口成功后退出不重复提醒；跳过/不再提醒从不执行。
- [原生 AppKit 探针](appkit-native.log)使用逐字复制的生产退出代理与模拟依赖，实际 terminateLater/reply 循环通过；[探针脚本](check-appkit-termination.py)可重现，生成源文件/二进制已清理，生产委托摘要见 [哈希](appkit-delegate-hash.json)。初始 harness 调试记录保留。
- [独立复核](review.md)未发现重要问题。[正式构建](package.log)通过 Core 契约、完整 315 项 XCTest 和 1270 条双语检查；[包自检](verification.log)包含新版关闭/退出回归、SDK 27.2 与最低 macOS 13.0 记录、签名和既有清理回归，均通过。
- [DMG](dmg.log)、[安装核对](installation.log)、[产物摘要](artifact-check.json)确认构建、安装及只读挂载镜像版本、App/Helper 元数据、严格签名、Automation entitlement 与三个执行文件 SHA-256 一致。已安装 /Applications/SuperCleaner.app，交付 [0.4.25 DMG](../../build/SuperCleaner-0.4.25.dmg)。
- [原生确认取消](native-observation.md)通过；[最终审计](final-audit.log)确认源码与构建时一致、版本未额外递增、HEAD/暂存区未变。删除本轮探针生成物与安装备份，保留可复现脚本和日志。

反思与评分：局部单一确认/执行入口 100/100；全局将清空结果、容量读取和退出 reply 连成一致的生命周期 100/100；实际 AppKit 退出循环回归 95/100，均已实施。无新增依赖，Swift 项目无需 requirements.txt/conda。根目录没有 AGENTS.md 或 .trae/rules/project_rules.md，未创建额外规则；测试素材只放 Tests。
