# 取消固定校验期限与共享模型规则

日期：2026-11-22。

## 结论

外层固定 60 秒不是文件安全判断的必要依据。应用归属校验改为等待真实完成或用户显式停止，不再因该计时器跳过项目。保留后台只读任务及一次性回复门禁，Stop 可结束等待；阻塞系统读取即使迟到完成，也不能授权任何文件移动。外部命令自身的执行边界、扫描完整性与清理计划有效性检查不在本次取消范围内。

内部路径校验与共享判断是两件事：前者只验证本次计划/候选对应的恢复目录和无链接祖先；后者来自 Ollama 的实际模型清单引用。

## 共享文件怎么判断

1. 读取 `.ollama/models/manifests` 下全部已支持布局的模型/tag 清单，包括没有勾选的模型。
2. 读取每份清单的 `config` 与 `layers` 中的 SHA-256 标识，映射到 `.ollama/models/blobs/sha256-…`，建立 blob → 引用它的所有清单的集合。这里使用清单中的内容地址，不通过名字相似或文件大小猜测共享。
3. 如果某 blob 的全部引用清单都被选中，将该文件加入本次执行计划，按路径去重，安排在清单之后处理。
4. 执行时先移除清单，随后在每个 blob 实际移动前重读当前引用关系。只有已无任何存活引用，才能移动。

| 选择和实际结果 | 共享文件 |
| --- | --- |
| A、B 共享，只有 A 被选中 | 保留，B 仍需要 |
| A、B 都选中且清单都成功移除 | 本次处理一次 |
| A、B 都选中，但 A 的清单移除失败 | 保留，A 仍需要；B 的独占文件可继续处理 |
| 扫描后新增 C 的引用 | 保留，不能仅相信旧扫描 |

恢复快照独立保存所删模型的依赖，不是存活模型的引用，不会让无引用的原始 blob 被永久保护。默认处理是移入废纸篓；物理空间仍要等废纸篓与保留快照按策略释放。本次核查发现上述共享逻辑已经实现，不修改正确的选择与引用算法。

## 逐文件复核

| 文件 | 本次修改与原因 |
| --- | --- |
| [ApplicationValidation.swift](../Sources/CleanerCore/ApplicationValidation.swift) | 从 ApplicationValidationDeadline.swift 改名，删除错误类型、秒数参数和计时任务；保留取消、错误传播、只读工作和一次性回复。 |
| [Execution.swift](../Sources/CleanerCore/Execution.swift) | 移除超时参数和属性，初验与终验调用无固定期限的校验入口；身份、保护、规则、运行状态和有效性复验不变。 |
| [ExecutionTests.swift](../Tests/CleanerCoreTests/ExecutionTests.swift) | 由自动超时案例改为明确点击停止，检查不等阻塞读取、不启动后项、迟到无移动。 |
| [UninstallAssociationBudgetTests.swift](../Tests/CleanerCoreTests/UninstallAssociationBudgetTests.swift) | 新增慢校验可以完成，保留 80 项整批校验；移除已经废弃的注入超时参数。 |
| [PackageReceiptCleanupTests.swift](../Tests/CleanerCoreTests/PackageReceiptCleanupTests.swift) | 失败注入改用正常校验拒绝，保持安装凭据仅在文件成功移除后处理的断言。 |
| [OllamaModelCleanupTests.swift](../Tests/CleanerCoreTests/OllamaModelCleanupTests.swift) | 补充两模型都选择但一份清单失败时的真实执行测试，证明仍需共享文件保留且另一模型独占文件继续删除。 |
| [en](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[zh-Hans](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 移除无调用的外层校验超时消息。 |
| [README](../README.md)、doc/docs 架构与开发入口、[前次修复](cleanup-execution-repair.md) | 同步当前无固定期限、显式取消与共享关系规则；历史发布文档保留原版本事实。 |

## 自我复核

- 局部：删除未经证据支持的外层截止时间（95/100），已执行；取消能力不能随计时器一起删掉（100/100），已执行并回归。
- 全局：按实际存活引用而非勾选意图决定 blob 清理（100/100），现有实现符合，补测失败分支；不重复改写已正确的算法。
- 没有新增依赖，不创建 requirements.txt；项目为 Swift。`.trae/rules/project_rules.md` 不存在，遵循用户提供的规范。测试素材位于 [Tests/validation-cancellation](../Tests/validation-cancellation)，不重试用户真实删除。

## 验证证据

旧实现注入 10 毫秒期限、执行 50 毫秒只读校验时，新增案例复现“跳过而非成功”。移除计时器后 Debug 全量 356 Core + 11 App 测试通过。该用例验证期限误判，不宣称实际等待过 60 秒；取消固定 60 秒还通过删除所有计时任务、参数和旧错误引用的源码复核确认。

中英文消息检查通过，共 1278 条。独立只读复核确认取消与成功竞争时只有一次回复，执行器移动前仍检查取消；共享规则和真实文件失败分支测试符合要求。

发布构建为 0.5.19（164），[Version.json](../Version.json) 由标准构建流程递增，以区分取消期限前后的应用。Release 同样通过 356 Core + 11 App 测试，核心契约、应用结构/稳定签名/启动及清理自检通过。新增 [发布记录](release-0.5.19.md) 与 [测试记录](../Tests/validation-cancellation/README.md)，分别说明可交付产物与验证材料。

[安装包](../build/SuperCleaner-0.5.19.dmg) 已只读挂载核对 0.5.19（164）及严格签名，通过后卸载；打包临时目录已清理。没有安装替换、重新执行用户删除或提交代码。逐项 diff 复核确认本轮改动仅取消固定期限、保留取消安全、增加必要回归并同步文档；既有 `build/SuperCleaner-0.5.10.dmg` 删除状态未干预。
