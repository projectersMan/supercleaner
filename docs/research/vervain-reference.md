# Vervain 对 SuperCleaner 的借鉴研究

访问日期：2026-11-16。外部仓库：[yakupbulbul/Vervain](https://github.com/yakupbulbul/Vervain)。本次固定读取 `main` 的提交 [`d48be5e713d55e42de917e59c44ab306e5756358`](https://github.com/yakupbulbul/Vervain/commit/d48be5e713d55e42de917e59c44ab306e5756358)，提交日期 2026-11-10，对应 2.2.0。通过 GitHub connector 读取目录、源码、测试及工作流；没有编译、运行或克隆外部代码，也没有验证其性能、实机权限行为及发布产物。

研究时的本项目对照基线：`1062a42`。下列评分为当时对本项目的采用优先级判断，满分 100，不是性能测试或成熟度评分；研究评分本身不代表功能实施或验收，后续状态见下文。

## 后续实施状态

本文保留原研究基线和外部源码结论；其中“尚未接入”、评分及待验证项指研究时点，不是当前功能清单。当前已将本地 AI 模型和项目产物接入独立 GUI 模块，整体为系统、应用、重复大文件、Agent、本地 AI 模型、项目产物六维度。模型按七类供应商的十个固定根发现，项目复用已有 scanner 并支持多选根目录，两者均零预选并保留活动、凭据、权限与不完整检查保护。Ollama 整库、HF 整仓库、Keras/GPT4All 范围约束见 [本地模型扫描器](../../Sources/CleanerCore/LocalAIModelScanner.swift)，页面见 [ResourceCleanupView](../../Sources/CleanerApp/ResourceCleanupView.swift)。

[DiskCapacitySnapshot](../../Sources/CleanerCore/DiskCapacitySnapshot.swift) 已提供 Home 所在卷的真实 total/available/used 读取及失败状态，不计入 purgeable，也未将回执逻辑字节改称物理释放。目录分布、跨卷前后采样和 CI 等其他研究建议不因本批接线自动视为完成。独立用户 CLI 已删除；项目扫描能力仍在 [ProjectArtifacts.swift](../../Sources/CleanerCore/ProjectArtifacts.swift)，配置、保护和只读检查由直接 Core 契约保留。实现范围见 [本批计划](../history.md)，实际测试和发布验收另以最终记录为准。

## 结论与研究基线

有借鉴价值，主要在于把已有扫描能力做成明确的用户入口，以及补足模型供应商布局识别和自动化质量门禁。没有必要替换本项目现有安全执行、Helper 和恢复架构。

| 方向 | 本项目已经具备 | Vervain 的有效补充 | 建议价值 |
| --- | --- | --- | --- |
| AI 模型资源 | [AgentScanners.swift](../../Sources/CleanerCore/AgentScanners.swift:290) 有 `modelCache` / `agentModelCache`，并标为 review | 按 Hugging Face、LM Studio、Ollama 的实际目录布局发现与分组 | 95 |
| 项目产物 | [ProjectArtifacts.swift](../../Sources/CleanerCore/ProjectArtifacts.swift) 的 `ProjectArtifactScanner`；研究时的独立 CLI 现已退役，当前 GUI 见 [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 独立 GUI、按项目归并、展示闲置证据及构建工具类型 | 94 |
| 磁盘展示 | [DiskUsageScanner.swift](../../Sources/CleanerCore/DiskUsageScanner.swift:49) 有家目录树；[DiskSpaceView.swift](../../Sources/CleanerApp/DiskSpaceView.swift:53) 已有容量摘要与目录树 | 卷容量、可用空间、可解释的分布图与下钻 | 90 |
| 持续验证 | [build-app.sh](../../Scripts/build-app.sh)、[verify-app.sh](../../Scripts/verify-app.sh)、[publish-release.sh](../../Scripts/publish-release.sh) 已有构建、测试、签名及发布流程 | 把已有检查接入 push / PR / tag 工作流 | 94 |

研究基线的导航尚未为 Project Artifacts 提供独立入口，Agent 资源发现也未覆盖专用 HF / LM Studio / Ollama 根与布局；这两项差异已由上文后续实现承接。当前导航见 [AppNavigationPolicy.swift](../../Sources/CleanerCore/AppNavigationPolicy.swift) 和 [ContentView.swift](../../Sources/CleanerApp/ContentView.swift)，模型根独立维护在 [LocalAIModelScanner.swift](../../Sources/CleanerCore/LocalAIModelScanner.swift)。磁盘目录树继续沿用原有实现，没有为卷容量展示重写扫描器。

## 1. 按供应商布局扫描模型，保护共享数据

`AIModelsScanner.candidates(home:)` 不是按文件扩展名全盘找大模型：

- Hugging Face：从 `~/.cache/huggingface/hub` 识别 `models--`、`datasets--`、`spaces--` 仓库目录，转成人类可读名称；候选为仓库整体。
- LM Studio：支持 `~/.lmstudio/models` 和 `~/.cache/lm-studio/models`，按 publisher / model 分项。
- Ollama：只把 `~/.ollama/models` 整库作为一个候选。代码明确解释共享 blobs 的问题，界面提示单模型删除应使用 `ollama rm`。
- 其他工具覆盖 torch、whisper、keras、GPT4All 的固定目录。

这些规则在 [`AIModelsScanner.swift:97`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/AIModelsScanner.swift#L97)。`measure` 只保留达到 10 MB 的条目，全部 `.review` / `.medium`；默认选择策略因此不会勾选模型。见 [`AIModelsScanner.swift:164`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/AIModelsScanner.swift#L164) 和 [`CleanupSelectionPolicy.swift:17`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Models/Cleanup/CleanupSelectionPolicy.swift#L17)。

计量复用 `directoryStats`，跳过 symlink 文件，从而避免把 HF snapshots 指向 blobs 的链接重复计量。测试覆盖模型零预选、Ollama 整库、候选符号链接与 HF blob 不重复计量；这是源码中的测试意图，本次没有执行这些测试。见 [`FileUtils.swift:42`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/FileUtils.swift#L42)、[`AIModelsScannerTests.swift:40`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/VervainTests/AIModelsScannerTests.swift#L40)。

适配建议：在本项目现有模型分类上加入供应商布局发现，记录 provider、模型仓库/模型名、根路径、共享存储关系和重新下载成本。模型维持 review / 默认不选。Ollama 若暂不解析 manifest 与 blob 引用关系，先做整库展示与管理提示，避免直接把 blob 当作可独立删除的模型。

不要原样照搬：当前实现仅扫描固定默认目录，没有读取自定义模型根；`.keras` 等候选包含整个工具目录，并非逐文件验证“仅有模型”；也没有运行中模型检查。`directoryStats.inaccessibleCount` 没有合并到模型扫描返回的 `ScanMetadata`，模型扫描的权限覆盖度不能只看其 metadata。这些都是该文件和计量函数可见的实现边界，不应沿用“看见目录即安全删除”的推理。

## 2. 项目产物的价值在于证据与分组，不在于多扫目录名

`ProjectArtifactRule` 把候选名称和项目证据绑定：例如 `build` / `dist` 必须有相邻 manifest；Python venv 必须有内部 `pyvenv.cfg`。`findArtifacts` 避开符号链接、候选内部的 `.git`，发现产物后不再深入产物内部。最终按 project 分成 `CleanupCategory`，而非散列所有 build 目录。见 [`ProjectArtifactsScanner.swift:185`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/ProjectArtifactsScanner.swift#L185)、[`ProjectArtifactsScanner.swift:362`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/ProjectArtifactsScanner.swift#L362)。

它额外补充项目活跃证据：`GitActivityProbe.lastActivity` 取 reflog、最后提交、Git index、未忽略的修改/新增文件时间，与文件系统活动时间取较新值；便宜证据已表明活跃时不再执行完整 Git 列表。Git 调用固定可执行文件列表、`Process.arguments` 传参、禁用交互，活动探测带 10 秒 watchdog。见 [`ProjectArtifactsScanner.swift:72`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/ProjectArtifactsScanner.swift#L72)。

`evaluate` 只有 ignored 且达到 idle 门槛的产物才设为 safe / high；unknown 保持 review / medium，notIgnored 保持 review / low。测试覆盖缺少 manifest、嵌套仓库、symlink、近期 Git 活动及未知状态。见 [`ProjectArtifactsScanner.swift:309`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/ProjectArtifactsScanner.swift#L309)、[`ProjectArtifactsScannerTests.swift:64`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/VervainTests/ProjectArtifactsScannerTests.swift#L64)。

适配建议：先给已有 `ProjectArtifactScanner` 增加 GUI 入口，展示项目分组、产物类型、最近活动、保护原因，再按本项目证据模型补充 Git 活跃信号。不要建立第二套执行路径；继续使用现有 `CleanupExecutor`、日志和恢复协调器。

风险：ignored 只说明 Git 不跟踪，不能证明内容可重建；手工文件、未备份数据也可能在 ignored 目录。Vervain 的文件活动只看项目一层，Git 未提交文件最多检查 2,000 个，而且探测失败返回 nil；源码推断这些边界可能遗漏活跃证据，不能据此证明闲置。`GitIgnoreProbe.state` 本身也没有活动探测函数的 watchdog。本项目已有凭据、嵌套仓库、活动、trackedFiles 失败保护，应保留，并把“活动未知”作为保守状态，不直接移植 Vervain 的自动预选结论。

## 3. 磁盘图和清理评审衔接值得学，扫描内核不宜复制

`DiskAnalyzerService.analyzeWholeDisk` 并发扫描多个顶层根，用虚拟磁盘节点聚合，再用卷已用容量减去已扫描大小生成 `System & Other` 差额。`DiskAnalyzerViewModel` 有 breadcrumb 下钻、清理后的缺失节点裁剪，以及把用户选中的目录/文件送入通用评审的转换；目录和文件都标记 review。见 [`DiskAnalyzerService.swift:77`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/DiskAnalyzerService.swift#L77)、[`DiskAnalyzerViewModel.swift:116`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/ViewModels/DiskAnalyzerViewModel.swift#L116)。可视化使用 Swift Charts 的 donut、图例和选中回调，见 [`DiskPieChart.swift:16`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Views/DiskAnalyzer/DiskPieChart.swift#L16)。

适配建议：复用本项目 `DiskUsageTree` / `DiskUsageOutlineView`，补充卷总量、可用容量、目录分布与下钻联动。将“逻辑文件大小”“实际分配大小”“系统报告可用空间”分开；本项目当前摘要计量逻辑字节，Vervain 使用 allocated size，两个数不能直接横比。差额应标注为未归因容量，不能把差额全部断言为 snapshots 或可清理内容。

本项目 [CleanupSessionSummary.swift](../../Sources/CleanerCore/CleanupSessionSummary.swift:3) 和 [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift:58) 累计成功回执的逻辑字节，没有清理前后的卷可用空间采样。如果要展示“真实释放空间”，应增加同一卷、同一可用空间口径的前后采样，并保留 Trash、隔离区、APFS 共享与系统并发写入造成的差异；移动文件与实际空间增加分开报告。

不照搬的实现边界：

- 这不是结果流式扫描。progress 仅在顶层 root 开始时发送标签，最终树构造完成后才返回；不能由此声称大盘能逐步展示结果或扫描更快。
- `buildTree` 使用 `.skipsHiddenFiles`，深度边界的 `aggregateSize` 却使用空 options；由源码推断，隐藏资源的计量范围可能随深度变化。原测试只构造普通文件，没有证明隐藏目录的一致性。见 [`DiskAnalyzerService.swift:232`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/DiskAnalyzerService.swift#L232)、[`DiskAnalyzerTests.swift:22`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/VervainTests/DiskAnalyzerTests.swift#L22)。
- 全盘固定根与按名称跳过目录、遍历计数、最大文件榜单都有截断边界；未对硬链接/APFS clone 做唯一实体计量。`largestFiles` 从已构建树收集，深度边界下只累计大小的文件不会进入榜单。
- 源项目目标为 macOS 15，本项目为 macOS 13。借鉴交互和数据语义即可，UI 应在现有目标上实现，不因移植而抬高最低版本。见 [`project.yml:4`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/project.yml#L4)。

## 4. 将已有质量验证接入 CI，收益高于复制发布脚本

CI 对 push / PR 执行单元测试，输出 xcresult 覆盖率摘要并检查本地化；只读权限和同 ref 的并发取消有参考价值。见 [`.github/workflows/ci.yml:1`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/.github/workflows/ci.yml#L1)。tag 发布在测试后导入 Developer ID，执行签名、公证、staple 与 DMG 打包，最后创建 Release、清理临时 keychain。见 [`.github/workflows/release.yml:27`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/.github/workflows/release.yml#L27)、[`scripts/release.sh:36`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/scripts/release.sh#L36)。

本项目已经有构建、验证及发布脚本，但没有 `.github/workflows`。适配重点应是调用现有脚本，区分无需证书的 PR 检查和有凭据的 tag 发布，保留本项目已有生产签名、Helper 契约及恢复验证。不要再维护一份平行命令实现。

Vervain 的 CI 不能直接当作完整质量门禁：覆盖率只是摘要，没有阈值；本地化失败降为 warning；`-only-testing:VervainTests` 排除了仓库已有 UI tests；所读工作流没有上传 xcresult artifact。第三方 Actions 使用版本 tag，create-dmg 通过 brew 安装而未锁版本。可以借结构，但本项目应明确哪些检查必须失败、固定工具版本、留存失败产物。此次没有核查工作流运行结果，也没有验证其签名/公证产物。

## 5. 权限体验可以局部借鉴，不替代真实覆盖度

`FullDiskAccessProbe` 以 Mail、Safari、系统 diagnostics 的可读性给出 unknown / likelyGranted / likelyDenied，没有把探测包装成系统权威查询。`FullDiskAccessViewModel.openSystemSettings` 在应用重新激活后单次复查，避免固定延时早于用户设置完成。见 [`FullDiskAccessProbe.swift:25`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/FullDiskAccessProbe.swift#L25)、[`FullDiskAccessViewModel.swift:25`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/ViewModels/FullDiskAccessViewModel.swift#L25)。

可借鉴“从设置返回后刷新”这一交互点，但本项目已有权限引导及扫描诊断，是否还有具体刷新缺口需要实际对照后再做。探测不能证明所有目标根可读，尤其模型扫描没有传播计量权限错误；本项目应继续以实际目标路径的读取结果与 coverage 为准。该局部方向暂评 83 分，低于主要增量。

## 6. 通用评审与恢复体验可参考，安全内核应保留本项目方案

Vervain 用 `CleanupSelectionPolicy` 集中决定默认选择，`CleanupCoordinator` 统一评审状态机，确认界面可以展开查看全部高风险条目；`CleanupService` 执行前检查保护路径、父级符号链接、排除列表，以及普通文件是否扫描后改变。`TrashRestorer.uniqueDestination` 在原路径已存在时另起恢复名称而不覆盖。见 [`CleanupCoordinator.swift:90`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/ViewModels/CleanupCoordinator.swift#L90)、[`CleanupConfirmationSheet.swift:86`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Views/Cleanup/CleanupConfirmationSheet.swift#L86)、[`CleanupService.swift:23`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/Cleanup/CleanupService.swift#L23)、[`TrashRestorer.swift:44`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/TrashRestorer.swift#L44)。

本项目已经有 [Execution.swift](../../Sources/CleanerCore/Execution.swift) 多次身份、规则、活动和过期复验，[HelperFileOperations.swift](../../Sources/CleanerCore/HelperFileOperations.swift) 的 fd / O_NOFOLLOW 操作，以及 [CleanupExecutionCoordinator.swift](../../Sources/CleanerCore/CleanupExecutionCoordinator.swift)、[ExecutionJournalStore.swift](../../Sources/CleanerCore/ExecutionJournalStore.swift)、[HistoryStore.swift](../../Sources/CleanerCore/HistoryStore.swift) 的恢复与日志。Vervain 的路径级检查不能替代这些机制，`hasChangedSinceScan` 也只覆盖普通文件，不覆盖整个目录树身份或内容。

恢复实现还有边界：清理完后才异步记录 history；history 读取/解码失败返回空数组，写入失败由 `try?` 忽略。Trash 路径为空、被用户清空或移动后，恢复会失败。因此“移入 Trash”是恢复的前提之一，并不等于跨故障保证。见 [`CleanupCoordinator.swift:135`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/ViewModels/CleanupCoordinator.swift#L135)、[`CleanupHistoryStore.swift:31`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/CleanupHistoryStore.swift#L31)。该方向作为界面与交互参考暂评 80 分，不建议复制其执行或持久化实现。

## README 与源码核对后的边界

1. Project Artifacts、AI Models、Disk Analyzer 在 Vervain 中确有 GUI 分支，不只是 README 愿景，见 [`ContentView.swift:84`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/ContentView.swift#L84)。本项目的项目入口差异应单独解决。
2. “评审、确认”并非所有清理都必经额外确认页：`CleanupCoordinator.confirm()` 只有 alwaysConfirm 或存在 review/risky 时进入 confirming，否则直接执行。评审页上的用户操作仍然存在，不应把此差异说成静默自动删除。
3. README 的“都可撤销”须结合 Trash 是否仍存在、history 是否成功持久化理解；源码没有提供绝对恢复保证。
4. README 对“固定参数”的描述不够精确：Git 可执行文件和命令结构固定，但 `-C` 的项目路径与 check-ignore 的目录名来自文件系统。实现使用参数数组，不拼 shell；本轮未发现这一点构成 shell 注入，但不能说完全没有动态参数。
5. `freedBytes` 在文件移入 Trash 后立即累加，不能当作实测磁盘可用空间增量。`HealthScoreBreakdown.compute` 的 potentialScore 又把 safe junk + Trash 当作未来可用空间增长；只有先完成真正释放操作、再读取空间，才可证明实际增长。见 [`CleanupService.swift:70`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Services/Cleanup/CleanupService.swift#L70)、[`HealthScoreBreakdown.swift:92`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Models/HealthScoreBreakdown.swift#L92)。

Smart Scan 值得学习的是每项扣分可解释、建议可操作。它的 40/30/10/5 扣分上限、review 权重 0.25，以及应用数量扣分只是源码中的启发式，不是经验证的系统健康模型。更自然的本项目方向是先展示空间压力、可审阅字节、扫描覆盖度和保护原因；照搬一个健康分暂评 65 分。见 [`HealthScoreBreakdown.swift:76`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/Vervain/Models/HealthScoreBreakdown.swift#L76)。

## 采用顺序与待验证项

局部顺序：AI 供应商模型发现（95）和项目 GUI（94）；全局顺序：现有验证脚本接入 CI（94），统一磁盘计量语义与可用空间展示（90）。四项均有明确本地承接点，应在后续实现范围内分别设计与验证。

实施前仍需验证：模型自定义根与共享 blob 的处理边界；项目深层未提交改动、Git 失败/超时如何进入保护状态；逻辑字节与 allocated size 在 APFS、硬链接、稀疏文件上的表达；macOS 13 UI 兼容性；无凭据 PR、受保护 tag、Helper 签名及公证的 CI 执行环境。本次没有用静态研究替代这些验证。

MIT 实际文本允许使用、复制、修改和分发，并要求在副本或实质性部分中保留原版权声明与许可声明。若后续直接移植代码，应保留 `Copyright (c) 2026 Yakup Bülbül` 和许可文本；本轮只做源码分析，未复制产品代码。见固定提交的 [`LICENSE`](https://github.com/yakupbulbul/Vervain/blob/d48be5e713d55e42de917e59c44ab306e5756358/LICENSE)。
