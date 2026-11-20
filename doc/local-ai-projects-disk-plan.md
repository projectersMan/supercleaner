# 本地 AI 模型、项目产物与磁盘空间实施计划

## 目标与设计

按用户要求增加两个与 Agent 环境并列的独立维度：“本地 AI 模型”和“项目产物”，接入全扫描、单模块取消/继续、刷新、人工选择、确认、清理结果及恢复。清理中心增加真实文件系统容量的总量、已用和可用展示，清理量继续使用原有累计回执，不把移入废纸篓等同于实际释放。

项目是包含 package.json、Cargo.toml、Package.swift、pyproject.toml 等工程标记的源码目录；项目产物是依赖安装或构建生成的 node_modules、target、.build、build、dist 等目录。复用现有 ProjectArtifactScanner，保持 Git 跟踪内容、凭据、活动项目、身份变化和未知状态保护，不按目录名直接删除普通用户文件夹。

模型使用供应商布局发现：Hugging Face 按仓库、LM Studio 按 publisher/model，Ollama 先按整个 models 库展示以保护共享 blobs；其他工具仅识别明确模型/下载目录。所有模型和项目产物均需人工选择，不纳入系统一键默认清理。模型不跟随根或候选软链接，不删除工具配置、凭据或 App 自用模型，执行前重新核验范围与身份。

方案采用现有 ScanModuleID / SystemScanReport / AppModel 流程和同一 CleanupRuntime 执行器；不另外建清理通道。静态已知路径是发现规则，不是缺少必需配置时的默认参数。界面保持 macOS 13 原生 SwiftUI/AppKit，不新增依赖。

CLI 调用核对显示 GUI 直接使用 CleanerCore，独立 CleanerCLI / ReadOnlyInterface 只承担命令行解析与 JSON 输出；构建和契约检查中存在为 CLI 自身服务的调用。本批按用户授权移除独立用户 CLI、打包签名及相应传输契约，保留 CoreContractChecks、CleanerHelper、项目扫描和规则/安全行为的直接验证。

## 文件与接口边界

- 新增 LocalAIModelScanner.swift（及必要模型类型），提供 `scan(context:) async throws -> LocalAIModelInventory` 和执行复验；记录模型 provider、候选、覆盖与限制。
- 新增 DiskCapacitySnapshot.swift，用系统 statfs 返回真实容量或明确错误，不用 0 冒充读取失败；界面复用结果并在激活、扫描和清理后刷新。
- ScanModuleID / AppDestination 新增 localAIModels、projects；CandidateSource 新增 localAIModels，项目继续使用 projectArtifacts；模型 category 复用 agentModelCache。
- SystemScanReport 增加两个模块的数据与候选，保留渐进发布、运行令牌、快照重整及跨模块选择隔离。
- UI 用同一个 ResourceCleanupView 提供模型和项目两个独立页面，清理中心六行导航与容量面板；项目按工程分组，模型按供应商分组。
- 删除 CleanerCLI / ReadOnlyInterface 及专属调用，直接保留核心契约所验证的保护行为。

## 执行步骤

- [x] 先补模型发现/软链接/共享库/权限与执行复验、磁盘读取、六模块导航及快照重整的回归，观察缺失功能的失败。
- [x] 并行实现独立模型扫描、磁盘容量读取和 CLI 移除；主任务负责六模块核心接入、AppModel 与界面，避免修改同一文件。
- [x] 保证项目扫描带真实项目活动探测；新维度默认不选，显式选择后进入统一删除确认与恢复链路。
- [x] 更新中英文本地化、README、doc/architecture.md、doc/development.md 和相关现有 docs；更新研究报告的已实施状态。
- [x] 完整 Release XCTest 295 项、核心契约、1229 条语言检查、macOS 13 编译与独立复核通过；原生界面确认六入口、容量、项目页与目录弹窗。取消弹窗后自动化连接超时，未将目录提交后的实机流程标为已验证，见 Tests/local-ai-projects-disk。
- [x] 本批只递增一次版本，固定证书构建 App / DMG，检查产物和安装副本；逐文件 diff 说明必要性，清理临时材料，不提交或推送。

交付与边界见 [0.4.4 本地交付](release-0.4.4.md)；审查发现的模型最终复验和项目根刷新问题均已修复并经原审查者定向确认。

## 复核重点与自我批评

- 仅添加侧栏会漏掉进度、选择、刷新、执行、失败重试和清理后快照，需要贯通六模块，而不是做静态入口。
- 模型“可重新下载”不代表无价值；Ollama blobs 不能按普通文件逐个删除，HF 软链接不能重复统计或越界跟随。
- 项目“被 Git 忽略”不代表可重建；必须保留现有保护和执行前复验，未知活动状态不得降级为安全。
- 磁盘容量与累计清理是不同口径。容量读取失败可见，不伪造零；不承诺清理前后差值全部来自本应用。
- CLI 删除必须同步产品、打包、签名、文档和测试，不能误删 GUI/Helper 共用核心或契约验证。

局部建议：完整独立模型维度 98 分、项目维度 98 分、清理中心真实容量 96 分；全局建议：复用统一安全执行链 100 分、移除无 GUI 依赖的 CLI 90 分，均纳入本批。根目录无 AGENTS.md 或 .trae/rules/project_rules.md；保留既有未跟踪研究报告。项目为 Swift，无新增 Python 包和 requirements.txt。

容量刷新现行变更：0.5.5（150）依用户要求移除了普通应用激活触发点，启动、扫描、清理、恢复及清空废纸篓后的更新保留。上文激活刷新的早期方案已被 [现行架构](architecture.md) 取代。


现行策略补充（0.5.6）：依用户要求，项目产物不再检测或展示运行状态，活动和探测未知不限制选择或执行；路径、权限、身份、Git 未知、凭据、嵌套仓库及副本保留检查继续有效。前文活动限制记录仅为历史背景，现行边界和验证见 [现行架构](architecture.md)。
