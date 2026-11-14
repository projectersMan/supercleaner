# 应用卸载资格修正验证与逐文件复核

当前交付版本为 **0.4.2（116）**，重新编译与 DMG 打包记录见 [release-0.4.2](release-0.4.2/README.md) 和 [版本说明](../../doc/release-0.4.2.md)。此前 0.4.1 包记录保留用于追溯。

本次修正区分系统保护、运行状态和执行权限。三个分类互斥：系统应用只进入 Protected；其余应用运行中只进入 Running，未运行只进入 Uninstallable。Running 的复选框用于请求退出，退出后移入 Uninstallable 并复用预备卸载清单；重新启动则移回 Running 并清除卸载选择。All 保留全部应用。

## 本轮互斥分类纠正

上一轮将运行中第三方应用也放入 Uninstallable，是对需求的错误理解。最新实现恢复互斥分区，同时保留已修复的第三方权限误判、输入法系统身份误判及 Helper 执行校验。

- [exclusive-red.log](exclusive-red.log)：5 个定向测试出现 8 处失败，直接复现重复计入分类的问题。
- [exclusive-suite.log](exclusive-suite.log)：完整 Debug XCTest 261 项、0 失败，覆盖系统身份优先、三个分类无重复/无遗漏，以及运行状态反转。
- [exclusive-classification.log](exclusive-classification.log)：模型分类、运行应用只在 Running、系统应用只在 Protected、勾选退出自检通过。
- [exclusive-selection.log](exclusive-selection.log)：启动后离开 Uninstallable 并清除卸载选择、退出后复用清单等自检通过。
- [exclusive-build.log](exclusive-build.log)：固定签名构建成功，核心契约及 Release XCTest 261 项通过；已替换安装副本，内容/软链接一致且深层签名校验通过，见 [本轮包记录](exclusive-package-verification.txt)。
- [exclusive-ui-verification.txt](exclusive-ui-verification.txt)：新包实机 Uninstallable 21、Running 10、Protected 84，合计 All 115；Chrome 在 Uninstallable 搜索为 0，在 Running 为 1；Siri/Siri AI 在 Protected 为 2，在 Running 为 0。Uninstallable 已无退出按钮，最终恢复该默认范围，搜索与选择均清空。没有退出或卸载真实用户应用。

## 上轮验证证据（互斥纠正前的历史记录）

- 初始回归：11 个测试出现 15 处失败，明确复现只读应用永久保护、第三方输入法误标系统以及输入法路径被拒绝，见 [red.log](red.log)。
- 补充筛选/Helper 范围回归先失败，见 [scope-red.log](scope-red.log)。
- 输入法缓存的计划/执行不一致先失败，见 [cache-red.log](cache-red.log)；最终清单明确保留缓存，本体仍可选。
- Helper 安全回归先出现“校验应拒绝但移动成功、源应用消失”两处失败，见 [helper-red.log](helper-red.log)；将原实时校验前移到共同路径后通过。
- 最终完整 Debug XCTest：260 项、0 失败，见 [suite.log](suite.log)。包含真实权限拒绝后的重试/停止、退出后的预备清单复用、重新启动清除卸载选择、系统保护和输入法缓存保护。
- 核心契约通过；固定签名构建还会运行 Release 契约与 XCTest，见 [build.log](build.log)。
- GUI 模型自检通过，验证系统应用不进入 Running、第三方可勾选退出、过期系统清单不能进入删除批次，见 [gui-self-check.log](gui-self-check.log)。
- 响应性与清单身份复用自检通过，见 [responsiveness.log](responsiveness.log)；批次勾选/清理门禁自检通过，见 [selection.log](selection.log)。
- 本机只读分析通过：Chrome 6 项、SogouInput 9 项、XApp 5 项，均能生成卸载清单且无统计限制；Siri AI 为 protected、0 项，见 [installed.log](installed.log)。此检查按已退出状态构建计划，未实际退出或卸载这些应用。
- 双语文案 1182 条校验通过；`git diff --check` 通过。独立只读审查提出的 3 个问题均已修复，再审未发现新问题。
- 固定签名构建成功并覆盖 `/Applications/SuperCleaner.app`；构建与安装副本的文件内容、软链接一致，旧签名要求接受新包，深层签名校验通过，见 [包记录](package-verification.txt)。版本保持 0.4.1（115），未发布版本。构建仅有既存 `ApplicationUpdateModel.swift` 弱引用捕获警告，该文件未修改。
- 新安装副本实机验证完成：Uninstallable 31/115、Running 10/115；Running 搜索 Siri 为 0 项，Protected 搜索为 2 项。Siri AI 显示 Protected 和真实系统路径，无退出复选框；豆包输入法可勾选，勾选后 Quit App 启用，随后已取消。Chrome、SogouInput 在默认列表显示 Running · Quit to uninstall。最终恢复无搜索、无勾选的 Uninstallable 列表。此轮仅等待应用模块完成，系统清理和 Agent 已取消，不宣称完成全模块扫描，见 [界面记录](ui-verification.txt)。

## 逐文件修改与必要性

以下每处源代码修改均经 `git diff` 检查，未保留与本次目标无关的改动。

| 文件 | 修改与原因 |
| --- | --- |
| [ApplicationModels.swift](../../Sources/CleanerCore/ApplicationModels.swift) | 删除静态管理员需求字段及复制方法，保护身份只由系统属性决定，避免一次预检永久锁死应用。 |
| [ApplicationScanner.swift](../../Sources/CleanerCore/ApplicationScanner.swift) | 全量发现与单应用实时复核都停止以输入法类型/写权限判断系统保护，并核对实际系统路径。 |
| [ApplicationInventory+SharedDeclarations.swift](../../Sources/CleanerCore/ApplicationInventory+SharedDeclarations.swift) | 清理已删除字段的复制代码，保持共享声明补齐流程可编译且不恢复旧判断。 |
| [ApplicationListFilter.swift](../../Sources/CleanerCore/ApplicationListFilter.swift) | 三个范围互斥：Uninstallable 仅未运行非系统应用，Running 仅运行中非系统应用，Protected 为系统应用。 |
| [ApplicationUninstallAnalysis.swift](../../Sources/CleanerCore/ApplicationUninstallAnalysis.swift) | 新增独立 running 状态，移除权限预判及管理员保护分支，系统说明不再暗示退出即可卸载。 |
| [UninstallPlanner.swift](../../Sources/CleanerCore/UninstallPlanner.swift) | 去掉管理员预检阻断，使第三方 app 能生成清单；输入法缓存标为受保护，与既有执行规则一致。 |
| [ApplicationExecutionValidator.swift](../../Sources/CleanerCore/ApplicationExecutionValidator.swift) | 去掉同一错误权限阻断，保留系统、运行状态、身份及关联归属校验。 |
| [Execution.swift](../../Sources/CleanerCore/Execution.swift) | 将原最后目录校验前移为 Helper/本地共用路径，避免授权等待期间重新启动的应用绕过复核；保留取消、期限与身份检查。 |
| [FileSystem.swift](../../Sources/CleanerCore/FileSystem.swift) | 删除唯一用于错误保护预判的 canMoveDirectory API，不改变真实文件操作和错误上报。 |
| [ScanAccessTracking.swift](../../Sources/CleanerApp/ScanAccessTracking.swift) | 删除对应转发及已失效的 Protected 注释，保留扫描读权限跟踪。 |
| [PathPolicy.swift](../../Sources/CleanerCore/PathPolicy.swift) | 显式卸载本体允许两个第三方输入法目录中的 app；普通 Library 删除规则、系统路径和嵌套 app 保护保持。 |
| [HelperFileOperations.swift](../../Sources/CleanerCore/HelperFileOperations.swift) | 受限 Helper 支持全局输入法 app 隔离/恢复，同时对路径祖先执行所有者及模式校验，保留 O_NOFOLLOW。 |
| [HelperClient.swift](../../Sources/CleanerCore/HelperClient.swift) | 对齐输入法移动与恢复的路由，避免只开放选择却无法使用既有授权通道。 |
| [UninstallPermissionRecovery.swift](../../Sources/CleanerCore/UninstallPermissionRecovery.swift) | 真实拒绝时允许第三方全局输入法使用受限 Helper，保留 EACCES/EPERM 分类。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 运行中状态使用 running；同步既有模型自检以验证分类、选择和退出后的状态闭环。 |
| [ApplicationsView.swift](../../Sources/CleanerApp/ApplicationsView.swift) | 系统应用显示 Protected 且不画退出复选框；运行中第三方仍能勾选退出；仅 All/Running 提供退出按钮，Uninstallable 不显示退出按钮。 |
| [英文文案](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 删除错误管理员保护说明，新增退出后可卸载及输入法缓存保留原因。 |
| [中文文案](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 与英文逐项同步并校验占位符。 |
| [ApplicationContract.swift](../../Sources/CoreContractChecks/ApplicationContract.swift) | 将旧的错误保护/筛选预期更新为独立运行状态和系统保护，继续验证真实分析结果。 |
| [ApplicationDiscoveryContract.swift](../../Sources/CoreContractChecks/ApplicationDiscoveryContract.swift) | 同步运行中预备清单的状态预期，保持运行时不可执行。 |
| [ApplicationUninstallProtectionTests.swift](../CleanerCoreTests/ApplicationUninstallProtectionTests.swift) | 替换原本固化错误权限规则的测试，覆盖只读本体/父目录、权限变化、Apple ID、三分区无重复/无遗漏及运行状态反转。新夹具位于 Tests 内。 |
| [InputMethodProtectionTests.swift](../CleanerCoreTests/InputMethodProtectionTests.swift) | 验证后装输入法可卸载且缓存仍受保护，清单和执行规则一致。 |
| [HelperProtocolTests.swift](../CleanerCoreTests/HelperProtocolTests.swift) | 验证输入法 Helper 范围及授权恢复能力，系统/嵌套/穿越路径继续拒绝。 |
| [PathPolicyTests.swift](../CleanerCoreTests/PathPolicyTests.swift) | 验证只开放第三方输入法 app 本体，未开放 Library 通用删除。 |
| [PreparedUninstallTests.swift](../CleanerCoreTests/PreparedUninstallTests.swift) | 保留序列化后退出可复用原清单的断言，运行状态独立于保护状态。 |
| [HelperExecutionSafetyTests.swift](../CleanerCoreTests/HelperExecutionSafetyTests.swift) | 新增真实执行器边界回归：最后校验拒绝时，Helper 路径不得移走源 app。 |
| [README.md](../../README.md) | 更新面向使用者的范围、勾选和权限行为。 |
| [既有架构文档](../../docs/architecture.md) | 同步卸载状态和 Helper 支持路径，避免旧规则误导。 |
| [既有开发指南](../../docs/development.md) | 同步诊断方式及必须覆盖的回归条件。 |
| [关联扫描文档](../../docs/application-association-scanning.md) | 说明运行中第三方始终可见，但退出后才激活卸载清单。 |
| [doc/architecture.md](../../doc/architecture.md) | 按用户指定位置提供架构入口及卸载链路说明，引用既有完整架构文档。 |
| [doc/development.md](../../doc/development.md) | 按用户指定位置提供开发入口、约束和验证命令。 |
| [实施计划](../../doc/application-uninstall-eligibility-plan.md) | 记录根因、用户补充要求、步骤、执行边界及评分。 |
| 本目录日志与本记录 | 保存失败复现、最终验证及逐文件自审证据，不包含真实卸载记录。 |

## 自我复核与建议评分

最初若只删除 Protected 筛选条件，分析器、计划器和执行器仍会阻止卸载；因此删除错误字段与整条链路的拦截是必要配套。上一轮错误地把“具有卸载资格”和“当前可进入卸载列表”混为一谈，导致 Running 与 Uninstallable 重复；现在以系统身份优先、非系统应用按运行状态分区，并验证三分区总数与 All 一致且无重复。退出按钮只出现在 All/Running。输入法 app 解除系统误判后，缓存清单和 Helper 运行状态复核继续保持一致。

| 层面 | 必要建议 | 价值分 | 结果 |
| --- | --- | --- | --- |
| 局部 | 修正系统/运行筛选与系统复选框，删除静态管理员误判 | 100 | 已实施并验证 |
| 局部 | 三个分类互斥，Uninstallable 移除运行应用与退出按钮 | 100 | 已实施，失败回归转绿 |
| 全局 | 分区无重复/无遗漏及启动退出迁移回归，统一文档和安装副本 | 99 | 已实施，验证见本轮记录 |
| 全局 | 统一扫描、计划、执行授权与恢复路径 | 99 | 已实施并验证 |
| 全局 | Helper 与本地共用最后实时复核 | 99 | 已实施，失败回归转绿 |
| 局部 | 输入法缓存的清单可选性与执行保护一致 | 96 | 已实施，失败回归转绿 |

没有剩余达到 85 分的范围内必要修改。没有新增 Python 包或其他依赖，`Package.swift`/`Package.resolved` 无需变动，仓库没有 `requirements.txt`。未创建 AGENTS.md，未提交或推送。未实际卸载 Chrome、搜狗、XApp、Siri AI 或修改它们的权限；真实管理员安装/授权和特权卸载不以只读分析或虚拟文件系统回归冒充实机验收。
