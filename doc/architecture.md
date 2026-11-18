# 架构与扫描流程

SuperCleaner 使用 Swift 6 和 SwiftUI 构建 macOS 应用，核心扫描、计划和执行逻辑位于 [CleanerCore](../Sources/CleanerCore)，界面与状态协调位于 [CleanerApp](../Sources/CleanerApp)，受限管理员操作位于 [CleanerHelper](../Sources/CleanerHelper)。完整项目架构见 [现有架构文档](../docs/architecture.md)。

## 六个扫描维度

[SystemScanCoordinator](../Sources/CleanerCore/SystemScanCoordinator.swift) 统一调度系统清理、应用、重复大文件、Agent 环境、本地 AI 模型和项目产物，以同一个 generation 汇总到 [SystemScanReport](../Sources/CleanerCore/SystemScanReport.swift)。六个模块分别取消、继续与渐进发布；继续只重跑当前模块。清理中心与侧栏提供六个入口。[ResourceCleanupView](../Sources/CleanerApp/ResourceCleanupView.swift) 参照应用卸载与大文件页，提供独立搜索、范围与排序、全宽可折叠分组、三态选择及按需详情；复用 AppModel 选择与外层清理底栏，不再常驻巨大检查器。

- 本地模型：[LocalAIModelScanner](../Sources/CleanerCore/LocalAIModelScanner.swift) 按七类 `LocalAIModelProvider` 的十个固定模型位置发现资源，Hugging Face 整仓库、LM Studio 按模型、Ollama 整库；Keras 只检查 models/datasets，GPT4All 只列识别出的模型文件。界面按供应商分组，扫描结果默认显示 Cleanable，无可清理项回退 All；模型不预选，必须手动选择。运行或活动未知、凭据、不可验证路径、权限及预算问题保持保护；候选和祖先链接不接收，内部链接不跟随。独立 `validateForExecution` 复验布局范围、身份与目录元数据指纹，再进入公共执行链。
- 项目产物：[ProjectArtifactScanner](../Sources/CleanerCore/ProjectArtifacts.swift) 依据源码工程 manifest 发现 `node_modules`、`target`、`.build`、`build`、`dist`，按 `project-root` 证据分组。用户可在设置中通过 `NSOpenPanel` 多选根目录，由 `ProjectScanRootsStore` 持久化；设置保存已有报告时只重扫项目模块，无报告时只保存配置；首次全扫描仍沿清理中心的权限准备流程启动。模型和项目页不再提供页头按钮，扫描从清理中心启动，项目扫描根在设置管理。Git 已跟踪内容通过其它检查后可手选；设置开关决定是否自动勾选项目产物（包括 Git 跟踪项），初始关闭。未知 Git 状态、嵌套仓库目录、凭据、活动未知或检查失败仍保持保护；ignored 不构成安全证明，执行仍需确认。
- 两个新维度复用 `PlanBuilder`、`CleanupExecutor`、journal、历史和恢复，可清理预选项纳入首页全部默认清理，不复用 Agent 能力包含率预选。

模型验证与“是否允许执行期间内容变化”分开：目录和普通模型文件都严格拒绝扫描后变化；初始验证及实际移动前终验均执行，公共执行器在 Helper 未处理而回退用户态后也不能跳过终验。不能因模型禁止内容变化而省略移动前的活动、保护、范围和指纹检查。

资源筛选状态按目的页保存在 AppModel，列表、焦点与底栏隐藏选中数使用同一个 `visibleCandidates`。已知候选全集包含模型和项目，并保留原有同路径别名，使其他模块清理回执不会丢失资源选择，新增永久保护也会立即撤销对应勾选。

独立用户 CLI 已移除，生产 App 不再嵌入 `supercleaner`；CleanerCore、CleanerHelper 和 CoreContractChecks 保留。[CoreReadOnlyContract](../Sources/CoreContractChecks/CoreReadOnlyContract.swift) 直接验证扫描、计划、保护和只读行为，[包内规则契约](../Sources/CoreContractChecks/PackagedRuleConfigurationContract.swift) 通过契约工具自身进入 fixture app 验证资源和签名规则配置。

## 磁盘容量与清理计量

标题下直接展示三张安全卡，位于扫描按钮行上方；原副说明和扫描范围小字已移除。扫描按钮加大并与标题文字左对齐，清空废纸篓按钮加大并靠右。六模块行显示非零的默认清理数量与容量；手动维度不显示零值。全部默认清理汇总系统推荐、大文件预选、Agent 自动预选及项目可清理预选，排除已取消勾选、未就绪、保护和失败项；模块统计与底栏使用同一合并后的可执行集合。

[DiskCapacitySnapshot](../Sources/CleanerCore/DiskCapacitySnapshot.swift) 用 `statfs` 读取 Home 所在卷的总容量及当前用户可用容量，已用为总量减可用；不加入 estimated purgeable。侧栏容量条及可用空间在激活、扫描、清理后由 AppModel 自动刷新。读取失败保留明确错误，不回填 0。扫描候选和本次清理累计仍为逻辑字节，移动到废纸篓或恢复区不能等同于物理容量释放。

清理中心移除外层 ScrollView：标题下方的扫描/用时、紧凑容量、累计清理/清空废纸篓为三个同行等高区域，六行导航填充剩余高度，安全卡直接位于标题下、扫描行上方，移除原两行说明。长行说明使用单行与 tooltip，最小 detail 760×560 pt 不通过扩大窗口下限掩盖溢出。

顶部扫描与累计清理区域不使用容器底色或圆角框，仅靠布局区分；原生操作按钮和头部安全卡沿用已有样式。

## 应用卸载资格

应用卸载链路为 [发现](../Sources/CleanerCore/ApplicationScanner.swift) → [分析](../Sources/CleanerCore/ApplicationUninstallAnalysis.swift) → [计划](../Sources/CleanerCore/UninstallPlanner.swift) → 用户选择与确认 → [实时复核](../Sources/CleanerCore/ApplicationExecutionValidator.swift) → [执行](../Sources/CleanerCore/Execution.swift)。

- 系统保护：字面或实际路径在 `/System/` 中的系统应用，仅在 Protected 和 All 可见，不提供退出或卸载复选框。
- 运行状态：非系统应用正在运行时只进入 Running，未运行时只进入 Uninstallable，三个非 All 范围互斥；退出后复用预备卸载清单，重新启动后移回 Running 并清除卸载选择。
- 执行权限：不再将只读模式或父目录权限持久化为不可卸载状态，实际权限错误进入既有授权/重试流程。
- 第三方输入法：`/Library/Input Methods`、`~/Library/Input Methods` 中 app 本体可显式卸载；系统输入法、通用缓存清理保护、共享内容保护和用户保护清单继续生效。

卸载资格专项的历史改动与验证见 [实施计划](application-uninstall-eligibility-plan.md) 和 [逐文件复核](../Tests/application-uninstall-eligibility/README.md)。

本批正式编译自动递增为 0.4.26（140），版本由 [Version.json](../Version.json) 统一管理；构建、签名、镜像和安装均已通过本批验收。此前交付见 [0.4.5](release-0.4.5.md) 和 [0.4.4](release-0.4.4.md)。

## 清理后的关闭提醒

[TrashReminderState](../Sources/CleanerCore/TrashReminderState.swift) 以 AppModel 的本次累计清理字节数和 UserDefaults 偏好判断是否提醒，并记录本次会话已确认的容量；重新扫描不重置，新增清理后允许再次提醒。“不再提醒”跨重启保留。

[TrashReminderWindowObserver](../Sources/CleanerApp/TrashReminderWindowObserver.swift) 仅监听挂载的主窗口关闭，不替换 SwiftUI 窗口 delegate；[应用退出回调](../Sources/CleanerApp/CleanerApp.swift) 通过更新退出门禁后复用同一个 [TrashReminderController](../Sources/CleanerApp/TrashReminderController.swift)。关闭、手动清空及退出共用确认工厂和执行器；关闭提醒额外显示“不再提醒”，手动清空与明确退出不显示。明确退出使用 terminateLater/reply 等待可选任务结束，Cancel 保留 Trash 并允许退出；已同意清空的任务失败后显示错误也允许退出。红色关闭仍保留后台会话。累计容量不承诺实际释放空间。

首页的显式“清空废纸篓”操作由同一个控制器负责确认、异步 Finder 调用和反馈；关闭/退出和首页只使用一个确认、执行和结果处理入口。成功且 Finder 确认已空后，只确认启动时的累计字节，不改写永久关闭提醒偏好；取消或失败保留提醒，期间产生的新清理仍可触发下一次提醒。操作结束刷新磁盘容量并等待本次测量完成，忙碌状态同时约束 UI、执行入口和退出，防止重复或交错操作。

跨模块默认计划通过 DefaultCleanupSelection.buildPlan(using:) 将原始候选先交给 PlanBuilder；不得将已去重的展示候选直接当成计划输入，以免系统安装包别名或父目录遮蔽大文件保留副本证明。执行和回执使用最终 plan.selectedItems。

本批交付与验证见 [0.4.26](release-0.4.26.md)。

三张安全卡和下方操作行统一使用左 52pt、右 24pt 的外边距；左右边界分别对齐标题文字和废纸篓按钮右边缘，安全卡三列与操作行均用 12pt 间距，避免把边距分别加在首列与末列。

Scan 按钮可见高度为 56pt（约原来的两倍），使用专用 SwiftUI ButtonStyle 保留按压、禁用、焦点轮廓和原生 Button 无障碍语义，计时在按钮右侧，左右外边界保持一致。模型/项目页的顶部 NSButton 复选框显示本地化 Select All/全选，组内仍为无文字小复选框；顶部摘要至少 200pt，计数使用固有宽度，ViewThatFits 在窄窗口分行。Project Artifacts 的标题、侧栏和首页统一来自同一个翻译条目。

设置中的项目扫描目录与项目页共用 `ProjectScanRootsStore` 和 `project-scan-roots.json`，不复制存储。44pt 行、132pt 内部滚动视口只限制可见三行，完整目录列表仍保留；草稿添加/移除后统一保存或撤销。设置首次保存不触发扫描，已有报告只刷新项目模块。保存与新扫描、权限流程继续、取消模块续跑及清理互斥；取消刷新后范围不一致的旧项目结果不可执行。配置错误在设置和项目页均可见，包括无扫描报告时。

资源默认入口只在本模块成功发布新结果时应用：模型仅清除旧模块选择、不预选；项目清除旧 ID 后仅在设置 projects.preselectArtifacts 开启时预选可清理项（含 Git 跟踪项），初始关闭。项目仅保留 All / Protected / Selected，初始有选项使用 Selected，否则 All；模型非空可清理集合使用 Cleanable，否则 All。无关发布、同 generation 最终汇总及导航不覆盖用户手动选择和筛选；本模块重扫重新应用上述默认。Cleanable 是安全可选资格，不判断模型是否还有用途。首页默认队列始终排除模型，包括手动选中的模型。

Agent 显示筛选用同名计算属性解析可选的 Published 手动覆盖：自动模式按当前 Skill/MCP 类型及平台判断 Selected 是否有结果，空则 All；不使用已过滤列表反推默认，避免循环依赖。异步选择变化可更新自动默认，手动选择则保持；类型切换清理 Skill/MCP 可见缓存。过滤前只解析一次有效范围，保持线性工作量。大文件页原默认就是 All Large Files，本次没有新增或更改其范围与预选规则。

编译版本由 build-app.sh 在基础预检之后、首次 Swift 编译之前调用 version.py next-build 分配一次，复用严格校验与原子写入；返回的版本/构建号冻结给 App 与 Helper。每次重编也递增，单独 verify/DMG/publish 只读同一配置；CI 构建号必须较旧号增加并写回源，避免打包与发布的版本来源分离。

上一轮资源汇总和 DMG 归属见 [实施计划](cleanup-center-resource-sync-plan.md)。ProjectArtifactScanner 识别工程内独立及构建目录内的 DMG；Git 跟踪、路径/身份/活动检查继续用于执行复验。ProjectInstallerOwnership 从大文件展示清单和树中排除已归项目的 DMG，原始候选保留以便刷新与副本保留证明校验。项目/大文件渐进结果先后不影响最终归属。构建进程目录仅进入 projectActivePaths，具体文件仍进入 activePaths；项目目录保持活动保护，未打开 DMG 不因 cwd 被整目录保护。项目根待刷新时，首页排除旧项目默认项。验收与逐文件审计见 [本批记录](../Tests/cleanup-center-resource-sync/README.md)。

项目 DMG 接管大文件副本时保留 largeFileProof，并保护其保留文件及覆盖该文件的目录。项目范围变化按路径迁移已选/撤选状态，不重新勾选人工撤选；单项取消子 DMG 时同步取消包含它的目录，选中目录包含其可清理子项。分组和首页容量都按最终目录操作去重。

本轮更新见 [计划](project-installer-discovery-plan.md)。项目 DMG 发现与副本证明由 ProjectArtifactScanner 承担；大文件发布前依据同一项目根/manifest 规则排除其清单与容量树，避免临时默认数后续消失。正式 App 显式链接实际 SDK 与独立的 macOS 13 最低版本，记录 DTSDKName 并与 Mach-O 复核。删除手动标题栏背景干预，由原生 NavigationSplitView 和 unified 工具栏管理边界；不再混淆 SDK 与最低系统版本，不使用固定偏移。模型保留分类，但始终手选；证据见 [验证记录](../Tests/project-installer-discovery/README.md)。

当前布局更新：磁盘从清理中心移至 Tools 下方的侧栏底部，显示硬盘图标和“磁盘空间”标题、容量条及可用空间；继续共用 AppModel 的读取、错误与自动刷新状态，不复制数据源。侧栏和清理中心底栏共用 SidebarSurface 的不透明系统底色，跟随系统外观，避免桌面透色差异；其它维度底栏继续使用原 bar 背景。见[实施计划](dashboard-sidebar-footer-plan.md)和[逐文件验证](../Tests/dashboard-sidebar-footer/README.md)。


本轮项目选择策略见 [实施计划](project-selection-preferences-plan.md) 和 [逐文件验证记录](../Tests/project-selection-preferences/README.md)。设置切换即时更新既有结果和首页缓存，关闭仅撤销自动选择，不清空人工决定；扫描或执行期间禁用开关。Git 跟踪 DMG 使用同一手选快照边界，仍检查路径、权限、云盘、包、保护和活动；不加入自动副本保留证明。未知 Git 状态与其它保护继续执行复验。


关闭/退出清空的现行规则见 [统一弹窗计划](exact-trash-dialog-plan.md) 与 [原生回归](../Tests/exact-trash-dialog/README.md)：直接复用 requestEmptyTrash，无第二套弹窗，成功才确认当前字节，保留既有抑制偏好和退出等待。

应用卸载首次进入优化见 [性能计划](application-first-entry-plan.md) 与 [验证记录](../Tests/application-first-entry/README.md)。行级分析只准备当前应用，空选择汇总不生成全量计划；行与全量入口复用按 plan.id 缓存的 checkedUninstallPlan。保护根按批重新解析，每个候选仍检查实际物理路径，执行仍实时复验。报告和保护策略更新清空缓存，运行状态变化立即调整计划可用性。
# 维度进度与关闭提醒补充（0.4.27）

六个维度页统一使用 `ModuleProgressView`，保持原 Agent 提示的居中大转圈、14pt 间距、次级 callout 文案与 24pt 留白。`AppModel.moduleScanProgressMessage(for:)` 只读取当前模块 waiting/scanning 状态及全局任务是否活动；重扫旧结果不会抢先展示，已完成模块不受其它任务影响。Agent 列表准备和覆盖分析继续复用它。

`TrashReminderWindowObserver` 把关闭请求交给会话级 Controller。繁忙时保留一次 Combine 订阅，状态发布后在主 RunLoop 检查可用性；空闲时释放订阅，再走原 `remindIfNeeded → requestEmptyTrash`。这样窗口视图消失不会丢失提醒，不引入轮询或另一种确认框。具体反馈时序未被现场重现；已验证的缺口与回归见 [计划](module-progress-trash-reminder-plan.md) 和 [验证记录](../Tests/module-progress-trash-reminder/README.md)。
订阅合并父模型与 Helper 发布。关闭后的清理完成结果通过原 dismissDeletionSheet 解除呈现门禁；执行中的原 guard 仍保持，清理统计与恢复记录不受影响。
# 0.4.28：清空结果与退出意图独立

Controller 的 Bool 只表示清空结果。明确退出时 delegate 等待公共任务结束，释放 terminationTask 后始终 reply(true)：Cancel 保留 Trash 并退出；已同意清空的任务仍等待执行、容量刷新和必要错误说明，失败也不否决退出。更新与正在进行清空的既有并发门禁保留。红色关闭按钮继续只关闭窗口，扫描与会话在 Dock 后台运行。见 [实施计划](quit-without-emptying-plan.md)、[真实进程退出回归](../Tests/quit-without-emptying/README.md)。
# 关闭提醒与清空资格（0.4.30）

`canBeginTrashEmptying` 保留实际清理、结果 sheet、权限、更新与 Helper 等互斥，只读扫描不阻塞清空。关闭和手动入口都先取得清空锁再显示确认，因此显示的 Empty Trash 总能执行；不再保留“只可提示但不能清空”的分支，也不停止或排队等待扫描。

`TrashEmptyingConfirmation` 同时返回清空意图与抑制选择。同一个工厂仅按关闭来源决定 checkbox，不再接受禁用清空的参数。抑制只写原 UserDefaults key，成功清空才更新已确认容量。Settings 用同一 key 恢复自动提醒，手动清空始终确认。`willTerminateNotification` 同步停止关闭提醒并清理 pending，避免明确退出后系统关闭窗口造成第二次确认。

现场 299 MB 已计账但 Agent 仍在扫描；0.4.29 提示虽及时出现，按钮仍禁用，0.4.30 移除此限制。大文件扫描复用 DeletedContentScanExclusion 排除 Trash，模块进度接收不依赖清空锁。复现、增量理由及并发验证边界见 [计划](trash-during-scan-plan.md) 与 [验证记录](../Tests/trash-during-scan/README.md)。


## 0.5.0 发布版本分配

常规构建继续自动递增 patch/build；显式 `build-app.sh --version 0.5.0` 在同一分配入口验证目标严格增加，精确使用目标展示版本并递增 build。校验完成后才原子保存，App、Helper、验证及 DMG 复用同一份 [Version.json](../Version.json)。本轮汇总六模块、项目与本地模型、统一扫描提示、Trash 生命周期及界面调整；见 [发布记录](../doc/release-0.5.0.md)。
