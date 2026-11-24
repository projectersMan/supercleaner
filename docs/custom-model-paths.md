# 自定义本地模型目录

设置页以与“项目扫描目录”一致的标题分组展示“模型扫描目录”，不再使用独立折叠项。模型工具选择下方为目录计数和右侧“添加目录…”；目录行共用文件夹图标、等宽路径、移除、44pt 行高及分隔线，有目录时列表固定 132pt（约三行）滚动；没有目录时不创建列表或空状态占位，只保留工具选择、目录计数和添加按钮。移除最后一项后保存、撤销和错误时重新读取配置仍可见。原十个固定位置不变，不使用环境变量或猜测路径；ModelScope、ComfyUI 只按配置发现。

| 工具 | 应选择的存储根 |
| --- | --- |
| Hugging Face | 含 `models--组织--模型` / `datasets--组织--数据集` 的 hub 根 |
| LM Studio、ModelScope | 含“发布者/模型”两层目录的模型根 |
| Ollama | 含 `manifests` 和 `blobs` 的 models 根 |
| PyTorch、Whisper、GPT4All | 直接包含该工具支持的模型文件的目录 |
| Keras | 包含各模型子目录的 models 根 |
| ComfyUI | models 根；递归发现已知模型文件，不跟随链接 |

自定义目录仍按工具布局识别，模型默认不勾选。目录缺失、权限不足、凭据和链接限制照常可见，未完整验证的内容保持保护。

配置为 `~/Library/Application Support/SuperCleaner/model-scan-roots.json`，与项目目录独立；必需字段为 `schemaVersion: 1`、`roots`，每项必须含 `provider` 和文件 URL `url`。无文件表示未添加目录；已有文件格式错误必须报告，不自动重写。用户可明确保存有效目录或空列表修复配置。坏配置只阻断模型模块。

已有报告且空闲时保存只刷新模型模块，忙碌时下次扫描生效。配置变化或读取失败会禁止旧模型结果的选择与执行，并从首页计划排除；其他模块继续可用。执行前重读配置并复验，移除自定义根会撤销其旧候选资格，固定范围继续有效。清理执行期间禁用目录编辑。Ollama 回执记录原根，恢复不依赖之后的设置，共享文件仍按引用关系检查。

## 逐文件复核

以下均为本轮相对 0.6.17 的必要增量；未合并其他 0.6.15 交互或缓存改动。

| 文件 | 必要性 |
| --- | --- |
| [ModelStorageRoots.swift](../Sources/CleanerCore/ModelStorageRoots.swift) | 独立配置、必需字段校验、去重及原子保存。 |
| [Scanner.swift](../Sources/CleanerCore/Scanner.swift) | 上下文传递根并保留其他检查参数。 |
| [SystemScanCoordinator.swift](../Sources/CleanerCore/SystemScanCoordinator.swift) | 仅模型任务读取配置，隔离配置错误。 |
| [LocalAIModelScanner.swift](../Sources/CleanerCore/LocalAIModelScanner.swift) | 自定义根复用布局及身份/敏感文件/链接检查。 |
| [CleanupRuntime.swift](../Sources/CleanerCore/CleanupRuntime.swift) | 模型预检和移动前重新读取配置。 |
| [OllamaModelStorage.swift](../Sources/CleanerCore/OllamaModelStorage.swift) | 按所属根复验模型和共享引用。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 回执携带模型根。 |
| [Execution.swift](../Sources/CleanerCore/Execution.swift) | 记录根并复验同根共享引用。 |
| [OllamaModelRecovery.swift](../Sources/CleanerCore/OllamaModelRecovery.swift) | 根据回执根恢复，保留祖先与隔离边界校验。 |
| [CleanupReportReconciliation.swift](../Sources/CleanerCore/CleanupReportReconciliation.swift) | 清理后保留扫描根快照。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 配置状态、局部刷新及过期门禁。 |
| [ModelStorageRootsSettingsSection.swift](../Sources/CleanerApp/ModelStorageRootsSettingsSection.swift) | 复用设置布局进行目录编辑和错误显示。 |
| [PermissionsView.swift](../Sources/CleanerApp/PermissionsView.swift) | 接入现有设置页。 |
| [ResourceCleanupView.swift](../Sources/CleanerApp/ResourceCleanupView.swift) | 过期提示和选择禁用，复用工具名称。 |
| [英文消息](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文消息](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 对齐新增设置和错误文本。 |
| [LocalAIModelScannerTests.swift](../Tests/CleanerCoreTests/LocalAIModelScannerTests.swift) | 固定供应商集合独立于自定义供应商枚举，保留原发现范围断言。 |
| [CustomModelPathTests.swift](../Tests/CleanerCoreTests/CustomModelPathTests.swift) | 固定/自定义并存、撤销、坏配置隔离、去重、链接和缺失根。 |
| [OllamaModelCleanupTests.swift](../Tests/CleanerCoreTests/OllamaModelCleanupTests.swift) | 自定义根共享引用和序列化回执恢复。 |
| [CustomModelSettingsTests.swift](../Tests/CleanerAppTests/CustomModelSettingsTests.swift) | 独立持久化、坏配置撤销选择和总计划。 |
| [README.md](../README.md)、[架构](architecture.md)、[开发指南](development.md)、[文档索引](README.md)、[测试索引](../Tests/README.md)、[历史](history.md) | 使用方法、架构和回归要求与源码对齐。 |

局部建议：现有设置补充自定义根，**97 分，已实施**；全局建议：扫描、选择、执行、恢复使用同一根归属，**98 分，已实施**。无新增依赖。初次源码验证未打包；后按用户要求编译交付 `SuperCleaner-0.6.18.dmg`，Release XCTest 451 项及独立运行验证通过。目录布局统一及 System 置顶随后随 `SuperCleaner-0.6.20.dmg` 交付，完整 Release XCTest 455 项通过。未替换安装副本、提交或推送。

空目录紧凑显示随 0.6.23（199）交付；当前安装包见 [README](../README.md)。以上旧版本描述为当时交付事实，过渡安装包已清理，校验记录保留在 [历史](history.md)。
