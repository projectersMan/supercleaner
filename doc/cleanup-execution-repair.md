# 清理执行、收尾与废纸篓修复

## 已确认问题

- WorkBuddy 21 项中的关联项累计共用 15 秒验证额度，约 15.22 秒后有 5 项跳过；安装凭据 BOM 解析及无关诊断报告扫描在每项验证时重复执行。
- 保存阶段包含 Dock 同步，界面满进度且重复显示同一句话；必须保留写入恢复记录先于后续移动的顺序。
- 成功清空后按钮未置灰，Finder 脚本先清空后判断空，空废纸篓或并发清空可能返回 -128。
- Ollama 恢复快照位于受保护的应用数据目录，误用普通候选的保护校验。原回归使用 home/Quarantine，未覆盖生产目录。

## 修复边界与验证计划

1. 移除累计额度；2026-11-22 后续调整同时取消外层单次 60 秒截止时间，仅保留显式取消等待，单项实际校验失败不阻止后续项。
2. 对安装凭据重复解析使用文件版本验证后的有限缓存；普通关联项不扫描不相关诊断报告。安全决定仍按当前归属、引用、运行状态、身份和保护规则计算。
3. 区分记录保存、Dock 同步、废纸篓准备和实际移动；不虚构文件内进度，不删除必要恢复日志。减少可证明冗余的同步操作。
4. 成功清空后记录本次清理摘要，无新增时禁用按钮，零字节的新项目也应重新启用；空废纸篓幂等成功，真实失败仍展示。
5. 快照用计划目录、候选标识和无符号链接的专用内部校验，绝不放开整个 SuperCleaner 目录。用生产目录覆盖准备、恢复、清理、中断重试与伪造路径。

验证使用 Tests 下的隔离数据和模拟 Finder，不清空真实废纸篓、不重试用户真实删除。保留现有工作区中 build/SuperCleaner-0.5.10.dmg 的外部删除。本次不提交。

## 逐文件复核

| 文件 | 修改与必要性 |
| --- | --- |
| [ApplicationValidation.swift](../Sources/CleanerCore/ApplicationValidation.swift) | 删除累计额度和单次计时器；保留取消与只允许一次回复，停止后迟到结果无权移动。 |
| [Execution.swift](../Sources/CleanerCore/Execution.swift) | 移除外层固定时间限制和后项批量跳过；向模型恢复传入真实计划目录；增加收尾阶段类型。身份/路径/引用/规则检查及恢复顺序保留。 |
| [ApplicationReceiptDirectoryCache.swift](../Sources/CleanerCore/ApplicationReceiptDirectoryCache.swift) | 有界缓存版本验证后的 BOM 文本；每次核对当前版本，解析期间变化则抛错，不缓存归属或删除许可。 |
| [ApplicationInstallationInspector.swift](../Sources/CleanerCore/ApplicationInstallationInspector.swift) | 用上述缓存替代相同 BOM 的重复 lsbom 调用，仍逐次读取安装元信息并匹配当前应用。 |
| [ApplicationScanner.swift](../Sources/CleanerCore/ApplicationScanner.swift) | 普通缓存/偏好/容器复核不再扫描无关崩溃报告；诊断候选与完整发现仍保留原检查。 |
| [OllamaModelRecovery.swift](../Sources/CleanerCore/OllamaModelRecovery.swift) | 内部恢复路径采用计划/候选精确边界与无链接祖先检查，避免普通候选保护误拒绝；创建前即拒绝计划目录链接。 |
| [ApplicationDockService.swift](../Sources/CleanerCore/ApplicationDockService.swift) | 写入后的同步已完成时直接读取当前值核对，省去重复同步；并发变化检测仍保留。 |
| [CleanupExecutionCoordinator.swift](../Sources/CleanerCore/CleanupExecutionCoordinator.swift) | 持久化后单独报告 Dock 阶段；随后恢复保存阶段，不让 Dock 等待被误称为记录写入。 |
| [QuarantineMaintenanceCoordinator.swift](../Sources/CleanerCore/QuarantineMaintenanceCoordinator.swift) | 移动前的核对和日志准备独立上报；保留先日志后移动。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 新阶段文案与计时状态；现有自检辅助方法支持零字节新增，停止门禁覆盖新增阶段。 |
| [DeletionOperationSheet.swift](../Sources/CleanerApp/DeletionOperationSheet.swift) | 收尾不用满格进度冒充完成，展示当前操作说明和阶段用时。 |
| [TrashReminderController.swift](../Sources/CleanerApp/TrashReminderController.swift) | 成功摘要控制按钮；空篓前置检查；Finder 错误后的独立只读确认。取消、未确认与剩余内容仍不记成功。 |
| [TrashEmptyingCheck.swift](../Sources/CleanerApp/TrashEmptyingCheck.swift) | 既有自检显式传入新增字节量，保持原测试语义。 |
| [en 资源](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[zh-Hans 资源](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 补齐阶段描述与计时中英文文案。 |
| [UninstallAssociationBudgetTests.swift](../Tests/CleanerCoreTests/UninstallAssociationBudgetTests.swift)、[ExecutionTests.swift](../Tests/CleanerCoreTests/ExecutionTests.swift) | 80 项全部校验、慢校验完成、手动停止时未完成的只读检查不能阻塞收尾且迟到检查不能移动文件。 |
| [ApplicationReceiptDirectoryCacheTests.swift](../Tests/CleanerCoreTests/ApplicationReceiptDirectoryCacheTests.swift) | 未变化只解析一次，替换后重新解析，读取中变化拒绝且不污染缓存。 |
| [ApplicationScannerTests.swift](../Tests/CleanerCoreTests/ApplicationScannerTests.swift) | 无关诊断超时不影响普通缓存，诊断文件仍须验证。 |
| [OllamaModelCleanupTests.swift](../Tests/CleanerCoreTests/OllamaModelCleanupTests.swift) | 所有原模型回归改用生产路径，新增模拟 Trash、伪造路径和链接边界。 |
| [CleanupExecutionCoordinatorTests.swift](../Tests/CleanerCoreTests/CleanupExecutionCoordinatorTests.swift) | 验证废纸篓准备阶段先于实际移动。 |
| [TrashEmptyingTests.swift](../Tests/CleanerAppTests/TrashEmptyingTests.swift) | 成功置灰、重复调用、空篓检查、并发变空、非空失败及零字节新增。 |
| [README](../README.md)、[架构](architecture.md)、[开发](development.md)、docs 中现行入口与旧超时记录 | 用户说明、架构约束、验证要求同步；旧记录标为历史，避免继续指导使用已废弃额度。 |

## 自我复核与改进优先级

- 局部：用真实受保护目录代替简化测试目录（100/100），已实施；补齐创建前祖先链接检查（100/100），已实施。
- 全局：保持用户数据保护与内部事务路径校验分离（98/100），已实施；仅缓存原始解析结果、实时重算安全许可（95/100），已实施。
- 不通过加大整批额度或放开 SuperCleaner 目录掩盖问题。没有需要另行决策的低分扩展建议。

真实用户文件、废纸篓和失败的历史记录未被测试重放。实机总耗时受 Finder 与文件系统影响，不能把解析次数减少宣称为整个卸载过程的固定加速倍数。

## 验证结果

- 修复前回归复现：生产路径的模型快照触发 protectedPath；80 项关联校验只完成少量项目；空篓检查出现在 Finder 清空之后；准备移入废纸篓的阶段缺失。
- 修复后 `swift test`：354 项 CleanerCoreTests + 11 项 CleanerAppTests，共 365 项，0 失败。
- 现有应用自检：清空/关闭/退出复用、清理收尾、卸载权限暂停与继续均通过，未发送真实 Finder 清空命令。清理清单收尾基准为 85 项结果对 25,000 项扫描记录，约 0.278 秒；这不是系统 Trash 或 Dock 操作的耗时。
- CoreContractChecks 通过；中英文 1279 条消息、源码覆盖和占位符检查通过；`git diff --check` 通过。
- 独立安全复核完成：创建前计划祖先检查、读取期间变更失效、零字节新增状态均已确认。逐文件修改均服务于本次问题，未放宽普通候选保护。
- [Version.json](../Version.json) 由标准构建脚本自动从 0.5.17（162）递增至 0.5.18（163），用于区分修复产物；没有手动修改依赖版本。
- 标准构建成功：0.5.18（163），现有证书签名；verify-app 的结构、签名、启动、并发扫描/清理及 Trash 自检全部通过。
- 安装包 `build/SuperCleaner-0.5.18.dmg` 已生成并只读挂载核对：内含应用版本 0.5.18、构建号 163，深度严格签名验证通过；核对后卸载镜像。

2026-11-22 后续调整与新的验证结果见 [取消固定校验期限与共享模型规则](validation-cancellation-shared-models.md)。0.5.18 的测试与构建记录保持当时版本事实。
