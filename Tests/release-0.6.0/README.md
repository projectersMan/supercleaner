# 0.6.0 发布复核

本次汇总上次提交以来的全部源码、文档及最新安装包；详细功能回归分别见同级功能验证目录。历史发布说明记录当时结果，现行行为以 [0.6.0](../../doc/release-0.6.0.md) 为准。

383 项 Release 测试、核心契约、1300 条双语检查、完整应用自检、签名及 DMG 挂载校验全部通过。本机安装副本 203 个文件/目录/链接条目与构建产物一致，实际打开已确认新标题。

## 验证入口

- `build.log`：显式指定 0.6.0，构建号 176，核心契约与 Release 全量测试。
- `localizations.log`：1300 条双语消息、引用及占位符检查。
- `verify.log`：应用结构、稳定签名、启动及各流程自检。
- `dmg.log`：首次遇到系统资源忙；`dmg-retry.log`：同流程重试成功，创建镜像、只读挂载和签名验证通过。
- `installed-signature.log`：安装副本签名验证。
- [verify-install.py](verify-install.py)：不跟随框架链接，比较目录、链接目标及逐文件 SHA-256，并核对版本和双语标题。
- [install-verification.json](install-verification.json)：本机安装一致性结果。

日志沿用仓库忽略规则，仅保留本地；验证脚本、结果摘要和最新 DMG 随源码交付。无新增第三方依赖，Python 验证仅使用标准库。

## 未扫描状态追加调整

用户在首次推送尚未完成时追加：未扫描的模块右侧保持空白。仅为手动选择兜底提示增加已有扫描结果条件；扫描中、已完成选择及会话累计沿原分支展示。不增加新状态或改变统计口径。沿用尚未推送的 0.6.0（176），重新编译 App、签名并生成最终 DMG。`prescan-build.log`、`prescan-verify.log`、`prescan-dmg.log` 分别记录编译、完整应用自检和镜像校验通过。

等待用户进行中的扫描自然完成后，重新安装最终产物。安装副本 203 项一致且严格签名通过；原生界面已确认初始六行均无 Manual Selection Required，保留标题、导航和会话总计。

局部建议“复用现有扫描结果判断，不增加另一份是否扫描状态”100/100，已实施。

## 按文件复核

已检查自上次提交以来的差异。下列改动均服务于已有需求；本次升级不再扩展业务功能。

| 文件 | 修改及必要性 |
| --- | --- |
| `Sources/CleanerApp/AppModel.swift` | 按目标页读取选择、统一成功回执累计；目录选择复用原入口，收尾阶段独立计时。 |
| `Sources/CleanerApp/CleanupCenterSelectionSummary.swift` | 从既有选择派生推荐、手动或混合摘要，避免第二份选择状态。 |
| `Sources/CleanerApp/CleanupActionBars.swift` | 推荐清理命名与底栏提示一致，明确执行范围。 |
| `Sources/CleanerApp/DashboardView.swift` | 更新主标题；未扫描不显示手动选择提示，扫描结果存在后才显示；当前选择与累计分别展示，完成标记保留。 |
| `Sources/CleanerApp/DeletionOperationSheet.swift` | 展示真实收尾阶段及耗时，避免满格进度冒充完成。 |
| `Sources/CleanerApp/DiskSpaceView.swift` | 路径分组、折叠、三态选择和当前范围全选，移除重复计数。 |
| `Sources/CleanerApp/DiskUsageOutlineView.swift` | 复用现有文件行，保持原保护、勾选与 Finder 操作。 |
| `Sources/CleanerApp/ResourceCleanupView.swift` | 复用现有三态复选框，避免行为分叉。 |
| `Sources/CleanerApp/LargeFileDirectorySection.swift` | 路径结构自适应分组，搜索保持归属，组选择仅含可见可选文件。 |
| `Sources/CleanerApp/TrashEmptyingCheck.swift` | 自检适配显式新增字节量。 |
| `Sources/CleanerApp/TrashReminderController.swift` | 成功后无新增则禁用；空篓幂等，错误仅在确认已空后转成功。 |
| `Sources/CleanerCore/ApplicationDockService.swift` | 删除可证明冗余的写后同步，保留当前值复核。 |
| `Sources/CleanerCore/ApplicationInstallationInspector.swift` | 复用版本验证过的凭据目录解析结果。 |
| `Sources/CleanerCore/ApplicationReceiptDirectoryCache.swift` | 有界原始解析缓存，读取期间变化立即拒绝，不缓存删除许可。 |
| `Sources/CleanerCore/ApplicationScanner.swift` | 普通关联校验省去无关诊断扫描，诊断候选仍完整验证。 |
| `Sources/CleanerCore/ApplicationValidationDeadline.swift`（删除） | 移除固定期限实现，避免正常慢读取被错误跳过。 |
| `Sources/CleanerCore/ApplicationValidation.swift` | 保留只读校验、显式停止和一次性回复，迟到结果不能移动文件。 |
| `Sources/CleanerCore/CleanupExecutionCoordinator.swift` | 明确保存与 Dock 阶段，保持先日志后移动。 |
| `Sources/CleanerCore/CleanupSessionSummary.swift` | 同一成功结果同时累加模块与总计，按回执去重，保证可加和。 |
| `Sources/CleanerCore/Execution.swift` | 接入无固定期限的校验、真实收尾阶段及严格内部快照路径。 |
| `Sources/CleanerCore/OllamaModelRecovery.swift` | 精确验证事务/候选及无链接祖先，修复生产路径误拒绝。 |
| `Sources/CleanerCore/QuarantineMaintenanceCoordinator.swift` | 准备移入废纸篓独立报告进度。 |
| `Sources/CleanerCore/Resources/en.lproj/Localizable.strings` | 新英文标题、选择/累计及阶段文案；清除无调用的超时消息。 |
| `Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings` | 同步中文及占位符。 |
| `Sources/CoreContractChecks/CleanupRefreshContract.swift` | 累计接口提供实际执行候选归属。 |
| `Sources/CoreContractChecks/CleanupSessionSummaryContract.swift` | 验证新同源累计接口，移除旧调用。 |
| `Tests/CleanerAppTests/DashboardModuleSummaryTests.swift` | 验证导航、手选、六维累计、重复回执、重试和重扫。 |
| `Tests/CleanerAppTests/LargeFileDirectorySectionTests.swift` | 验证完整互斥分组、搜索稳定、无组数限制及可选边界。 |
| `Tests/CleanerAppTests/TrashEmptyingTests.swift` | 验证空篓、并发、失败、禁用与零字节新增。 |
| `Tests/CleanerCoreTests/ApplicationReceiptDirectoryCacheTests.swift` | 验证缓存复用、版本失效和解析期间变化。 |
| `Tests/CleanerCoreTests/ApplicationScannerTests.swift` | 无关诊断失败不阻断普通关联校验。 |
| `Tests/CleanerCoreTests/CleanupExecutionCoordinatorTests.swift` | 准备阶段先于真实移动。 |
| `Tests/CleanerCoreTests/ExecutionTests.swift` | 停止不等待阻塞读取，迟到结果不授权移动。 |
| `Tests/CleanerCoreTests/OllamaModelCleanupTests.swift` | 生产恢复路径、生命周期、链接拒绝与共享清单部分失败。 |
| `Tests/CleanerCoreTests/PackageReceiptCleanupTests.swift` | 失败夹具改用正常校验拒绝，保持凭据处理顺序断言。 |
| `Tests/CleanerCoreTests/SessionCleanupMetricTests.swift` | 六维与全局数量/原始字节一致，实际成功字节优先。 |
| `Tests/CleanerCoreTests/UninstallAssociationBudgetTests.swift` | 慢校验和大批关联全部完成，不因累计时间跳过。 |
| `Tests/large-file-directory-groups/make-fixture.py` | 可复现的隔离扫描输入，仅标准库，不接触用户文件。 |
| `Tests/cleanup-execution-repair/README.md` | 保存执行修复的失败基线与验证结果。 |
| `Tests/validation-cancellation/README.md` | 保存取消与共享模型回归证据。 |
| `Tests/large-file-directory-groups/README.md` | 保存目录分组验证结果。 |
| `Tests/large-file-directory-controls/README.md` | 保存批量选择与展开控制验证结果。 |
| `Tests/dashboard-module-metrics/README.md` | 记录用户澄清及统计回归范围。 |
| `Tests/release-0.5.30/README.md` | 保留前次已完成的打包安装证据。 |
| `Tests/release-0.5.30/install-verification.json` | 保留前次安装一致性结果。 |
| `Tests/release-0.6.0/README.md` | 本次交付与逐文件复核索引。 |
| `Tests/release-0.6.0/verify-install.py` | 可重复核对正式构建与本机安装副本。 |
| `Tests/release-0.6.0/install-verification.json` | 本次安装版本、标题与内容一致性摘要。 |
| `Version.json` | 按用户指定升级为 0.6.0，标准脚本递增构建号至 176。 |
| `README.md` | 当前使用方式、功能及新版安装包入口；校正切回应用的容量刷新描述。 |
| `doc/architecture.md` | 同源累计、目录展示、校验及模型恢复边界。 |
| `doc/development.md` | 当前验证与回归约束，更新正式交付入口。 |
| `docs/architecture.md` | 同步仍被引用的旧目录入口，避免现行规则冲突。 |
| `docs/development.md` | 同步验证约束与当前版本链接。 |
| `doc/large-file-duplicates-plan.md` | 默认展示与现行目录分组一致。 |
| `docs/uninstall-stall-0.3.33.md` | 明确旧固定期限已废弃，历史记录不冒充现行规则。 |
| `doc/cleanup-execution-repair.md` | 记录执行修复原因、边界和测试。 |
| `doc/validation-cancellation-shared-models.md` | 记录显式取消与实际共享引用规则。 |
| `doc/large-file-directory-groups.md` | 说明路径分组依据、取舍与验证。 |
| `doc/large-file-directory-controls.md` | 说明折叠、批选和搜索范围。 |
| `doc/dashboard-module-metrics-plan.md` | 保存最终验收口径，避免扩大详情页计数变更。 |
| `doc/release-0.5.18.md` | 执行、收尾、废纸篓与恢复修复历史。 |
| `doc/release-0.5.19.md` | 取消固定期限及共享引用验证历史。 |
| `doc/release-0.5.21.md` | 自适应目录分组历史。 |
| `doc/release-0.5.22.md` | 目录展开与三态选择历史。 |
| `doc/release-0.5.24.md` | 目录右键全局展开控制历史。 |
| `doc/release-0.5.25.md` | 移除重复顶部控制历史。 |
| `doc/release-0.5.27.md` | 筛选范围全选历史。 |
| `doc/release-0.5.28.md` | 精简重复计数历史。 |
| `doc/release-0.5.29.md` | 推荐文案与右对齐历史。 |
| `doc/release-0.5.30.md` | 双语标题及统计同步的前次安装历史。 |
| `doc/release-0.6.0.md` | 汇总上次提交以来的交付内容和本版验证。 |
| `build/SuperCleaner-0.5.10.dmg`（删除） | 接纳已有删除状态，用最新安装包替代过期交付入口。 |
| `build/SuperCleaner-0.6.0.dmg` | Git LFS 保存最新完整安装包；App 目录和缓存沿现有忽略规则。 |

## 反思及已实施建议

- 局部：版本配置、App、Helper、DMG 与本机安装逐项核对，100/100；通过标准构建和安装一致性检查实施。
- 全局：成功回执作为清理中心分维度与总计的共同来源，98/100；已有实现和回归覆盖，不再扩大详情页计数口径。
- 全局：发布只收纳源码、文档、必要测试证据与最新安装包，95/100；清除临时备份和自检残留，保持编译缓存与日志忽略。

上述改动有明确需求和验证目的，没有新增低价值扩展，也没有重新执行用户文件清理。清理容量仍为逻辑字节；签名为本机固定证书，本次不是 Apple 公证发行。
