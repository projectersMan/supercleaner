# 开发与验证

本地模型现行规则见 [现行架构](architecture.md) 和 [模型清理回归源码](../Tests/CleanerCoreTests/OllamaModelCleanupTests.swift)。不得重新引入基于 Python/Ollama 进程名的模型锁定或 In use 展示。模型名称与 tag 来自清单，共享引用贯穿选择、计划、执行及回执对账；快照必须保证跨回执独立恢复。底栏按模型计数、按实际文件去重计量，不能把底层文件误报为隐藏模型。定向回归覆盖共享保留、单项/多项、内容变化、引用新增、清单失败、分批删除、后批清理后前批恢复、恢复链接拒绝和中断快照清理。复用公共执行器和恢复记录，无新增依赖。

完整开发指南见 [现有开发文档](../docs/development.md)。本项目主体为 Swift，不使用 Python conda 环境；依赖声明保持在 [Package.swift](../Package.swift)，本次未新增依赖，也没有需要更新的 `requirements.txt`。

遵循先计划、后实现、再验证和逐文件 `git diff` 复核的流程，本批范围见 [项目发现与模型手选计划](project-installer-discovery-plan.md)；六维度接线历史见 [原实施计划](local-ai-projects-disk-plan.md)。导入放在文件顶部，不新增函数内定义或动态安装逻辑，不通过捕获错误掩盖失败。本批验证素材集中放在 [Tests/project-installer-discovery](../Tests/project-installer-discovery)，原批次材料保留。未发现根目录 `AGENTS.md` 或 `.trae/rules/project_rules.md`，不凭空创建工作流规则文件。

## 六维度接线与安全约束

新增维度必须同时检查 `ScanModuleID`、导航、报告 payload、协调器任务、渐进合并、默认选择、清理范围、执行复验和模块取消/继续。当前六维度为系统、应用、重复大文件、Agent、本地 AI 模型与项目产物，不能在 UI 或契约中硬编码成四个。模块回调同时校验 generation 与单次运行令牌，旧结果不得覆盖新扫描。

[LocalAIModelScanner](../Sources/CleanerCore/LocalAIModelScanner.swift) 是模型范围与布局的唯一来源；禁止把工具配置根整体当模型缓存。模型按供应商分组，固定根之外不宣称已扫描，页面保持资格分类但不预选，须手动选择并确认。执行复验必须保留范围、文件身份、元数据指纹和保护检查；模型不再检测或展示运行状态，单模块刷新和模型执行不请求进程活动数据。项目继续使用 [ProjectArtifactScanner](../Sources/CleanerCore/ProjectArtifacts.swift)，[ResourceCleanupView](../Sources/CleanerApp/ResourceCleanupView.swift) 按 `project-root` 展示，扫描根通过 `ProjectScanRootsStore` 保存；manifest、Git 及凭据证据不能用目录名或 ignored 状态替代。两个资源页不再提供页头按钮；扫描从清理中心启动，项目扫描根在设置管理；设置保存项目根已有报告时只刷新projects，无报告时只保存；清理中心首次全扫描必须保留原权限准备流程。

侧栏容量从 [DiskCapacitySnapshot](../Sources/CleanerCore/DiskCapacitySnapshot.swift) 的 `statfs` 结果读取。验证必须覆盖失败错误展示和刷新，不得以候选总量或回执逻辑字节推算物理空间，不加入 purgeable 估算。仅当项目默认勾选设置开启时，仍勾选的可清理项进入全部默认清理；模型手动选择且不加入该队列，链接边界、权限或预算无法确认时保持保护；模型进程活动不参与资格判定，项目运行状态同样不参与选择和执行资格判定。

首页按单页验收：移除外层滚动，顶部扫描/按钮下计时、紧凑容量、累计清理/清空按钮同行等高；最小 detail 760×560 pt、默认窗口及中英文本下六行导航和头部安全卡不能裁切。资源页复用应用与大文件的搜索宽度、范围/排序、全宽分组与选择操作；全选只覆盖当前可见且可清理项，不清除其它维度选择，保护项不能通过组勾选绕过。

顶部三个区域不添加容器底色或边框，保留等高布局和原生按钮样式；扫描按钮与标题文字左对齐，清空按钮加大并右移，不移除安全卡或列表悬停色。

资源页按 destination 保存 `resourceReviewFilters`，列表、焦点和底栏隐藏计数统一使用 AppModel.visibleCandidates；修改筛选必须清理缓存并重新核对焦点。新增维度也必须进入 `allKnownCleanupCandidates`，不能漏掉回执交集、保护撤选及同路径别名对账。实际 AppModel 回归已接入原导航自检，不只测试纯筛选函数。

清空废纸篓必须使用同一个 TrashReminderController：确认后异步请求 Finder，明确永久删除语义；成功并核对已空才记录启动时的累计清理量，保留原有 suppress 偏好。取消、拒绝权限、失败、超时不得伪造清空成功，必须尊重用户的提醒偏好；结束后刷新并等待容量读取完成。覆盖重复点击、忙碌执行/退出门禁与新清理量。正式 App 签名需包含 Automation entitlement 和本地化用途描述，不用主线程等待脚本，不直接 rm Trash。验证仅用假执行器和确认取消，不实际清空用户内容。

模型安全验证不可被 `allowsExecutionContentChanges` 之类的变化许可开关控制。目录和文件均严格拒绝变化，并分别覆盖初始验证、实际移动前终验，以及公共执行器 Helper 回退用户态后再次终验；模型目录内容在等待期间改变时必须阻止移动；模型运行状态不参与删除资格。

独立 CLI、参数解析及 JSON 传输契约已退役。保留 CoreContractChecks、CleanerHelper 和 GUI 共用 Core；只读与保护行为改用直接 Core 契约，正式规则资源仍用 fixture app 检查，不移除发布配置、签名或 Helper 门禁。

卸载相关修改须同时检查发现、筛选、分析、计划、实时复核、授权、恢复、界面勾选及文案，不能只放开列表却保留后续错误拦截。系统保护和运行状态必须分别建模；实际权限不足不得被静态预检永久归类为不可卸载。

Protected、Running、Uninstallable 必须构成应用清单的互斥分区：系统应用优先归入 Protected；其余应用根据是否运行分别进入 Running 或 Uninstallable。All 只是完整汇总。回归须验证三个范围无重复、无遗漏，并覆盖启动/退出迁移；Uninstallable 不显示退出按钮。

验证命令：

```sh
swift test
swift run CoreContractChecks
swift run CoreContractChecks --check-core-read-only
swift run CoreContractChecks --check-review-coverage
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
swift run CoreContractChecks --check-packaged-rule-config "$PWD/build/SuperCleaner.app"
```

真实应用的只读卸载验证只构建计划，不执行卸载或退出用户应用。既有专项结果及边界见 [历史验证记录](../Tests/application-uninstall-eligibility/README.md)，不据此声明本批六维度或产物验证已经通过。

版本统一由 [Version.json](../Version.json) 管理，编译脚本在首次 Swift 编译前调用 `version.py next-build` 自动递增 patch 与构建号；重复编译也递增，不再手动 bump。人类明确指定版本时使用 `./Scripts/build-app.sh --version <version>`，展示版本精确采用该值、构建号继续递增，并拒绝同版、降级或非法格式；后续普通编译继续递增 patch 与构建号。单独验证和 DMG 打包不递增；基础预检或版本校验失败不写入，开始编译后的失败保留号码。构建成功后使用 [create-dmg.sh](../Scripts/create-dmg.sh) 生成带版本号的 DMG，再挂载核对 App/Helper 版本与构建产物一致；本批结果见 [0.5.0](release-0.5.0.md)，历史记录保持当时的验证边界。

关闭提醒的实现与验证见 [计划](trash-close-reminder-plan.md) 和 [验证记录](../Tests/trash-close-reminder/README.md)。提醒资格必须使用 `sessionCleanupSummary.bytes`，0 字节不显示；已确认容量只在当前会话去重，“不再提醒”使用 `cleanup.suppressTrashReminder` 持久化。主窗口关闭与直接退出必须共用状态，最小化或其他窗口关闭不提醒，更新禁止退出时不得显示退出提醒。不得替换 SwiftUI 窗口 delegate，不得自动清空废纸篓或将清理累计量视为已释放空间。修改中英文资源后运行 `python3 Scripts/check-localizations.py`，定向回归为 `swift test --filter TrashReminderStateTests`。没有新增外部依赖。

全部默认清理必须复用 DefaultCleanupSelection 的可执行集合；系统与大文件默认项需仍在 selectedIDs，Agent 需同时属于自动预选 IDs。修改选中或自动预选时使缓存失效；分模块统计在全局父子/重复去重后计算，零值和手动维度不显示。三张安全卡直接放在标题下、扫描按钮行上方；不再展示原两行说明。回归覆盖 Agent 单独可执行、取消勾选、活动/保护、异步预选与扫描门禁；只读夹具不执行真实清理。

跨模块默认计划通过 DefaultCleanupSelection.buildPlan(using:) 将原始候选先交给 PlanBuilder；不得将已去重的展示候选直接当成计划输入，以免系统安装包别名或父目录遮蔽大文件保留副本证明。执行和回执使用最终 plan.selectedItems。

本批交付与验证见 [0.4.26](release-0.4.26.md)。

三张安全卡和下方操作行统一使用左 52pt、右 24pt 的外边距；左右边界分别对齐标题文字和废纸篓按钮右边缘，安全卡三列与操作行均用 12pt 间距，避免把边距分别加在首列与末列。

Scan 按钮可见高度为 56pt（约原来的两倍），使用专用 SwiftUI ButtonStyle 保留按压、禁用、焦点轮廓和原生 Button 无障碍语义，计时在按钮右侧，左右外边界保持一致。模型/项目页的顶部 NSButton 复选框显示本地化 Select All/全选，组内仍为无文字小复选框；顶部摘要至少 200pt，计数使用固有宽度，ViewThatFits 在窄窗口分行。Project Artifacts 的标题、侧栏和首页统一来自同一个翻译条目。

项目目录设置使用草稿和同一个持久化入口，三行视口不能裁掉保存范围；移除仅改配置。自检覆盖默认完整列表、去重、空列表、重开、实际写入失败保留旧配置、不触发首次扫描、只刷新项目、取消刷新后的旧范围门禁，以及保存时禁止新扫描/权限继续/模块续跑与清理。配置错误必须在项目页无结果时也可见。原生验收只编辑草稿后撤销，不改变用户真实配置，不执行清理；记录见 [设置验证](../Tests/project-scan-roots-settings/README.md)。

资源默认值须在 AppModel 模块结果边界应用，不能放在 View.onAppear 或每次报告变化时全选。回归覆盖两维度首次/渐进发布、受保护/空集合回退 All、旧 ID 替换、本模块刷新保留其它维度、搜索排序保留、用户取消后导航/无关发布/最终汇总不重选，并确认只有项目预选加入首页队列、模型无默认且手动选择不加入。使用既有导航自检与只读原生扫描，材料见 [验证记录](../Tests/resource-cleanable-defaults/README.md)。

Agent 默认空回退必须区分自动默认和用户主动筛选；Picker、列表和空态继续共用同一 agentItemsSelectionFilter。类型/平台/选择变化后缓存必须刷新，Skill/MCP 过滤循环内不得反复扫描全部列表来解析默认。回归包括延迟预选、自动 Selected/All 互换、手动空 Selected 和 All 保留、类型平台切换和既有性能门禁。大文件初始 All 已符合要求，手动空重复范围不自动切换。验证见 [本批记录](../Tests/agent-empty-default-scope/README.md)。

上一轮资源汇总和 DMG 归属见 [实施计划](cleanup-center-resource-sync-plan.md)。ProjectArtifactScanner 识别工程内独立及构建目录内的 DMG；Git 跟踪、路径/身份和内容检查继续用于执行复验。ProjectInstallerOwnership 从大文件展示清单和树中排除已归项目的 DMG，原始候选保留以便刷新与副本保留证明校验。项目/大文件渐进结果先后不影响最终归属。项目产物不检测或展示运行状态，目录及 DMG 的选择和执行均不受活动状态限制；完整扫描保留共享探针的具体打开文件，供其它维度沿用原有活动保护。项目根待刷新时，首页排除旧项目默认项。验收与逐文件审计见 [本批记录](../Tests/cleanup-center-resource-sync/README.md)。

项目 DMG 接管大文件副本时保留 largeFileProof，并保护其保留文件及覆盖该文件的目录。项目范围变化按路径迁移已选/撤选状态，不重新勾选人工撤选；单项取消子 DMG 时同步取消包含它的目录，选中目录包含其可清理子项。分组和首页容量都按最终目录操作去重。

本轮更新见 [计划](project-installer-discovery-plan.md)。项目 DMG 发现与副本证明由 ProjectArtifactScanner 承担；大文件发布前依据同一项目根/manifest 规则排除其清单与容量树，避免临时默认数后续消失。正式 App 显式链接实际 SDK 与独立的 macOS 13 最低版本，记录 DTSDKName 并与 Mach-O 复核。删除手动标题栏背景干预，由原生 NavigationSplitView 和 unified 工具栏管理边界；不再混淆 SDK 与最低系统版本，不使用固定偏移。模型保留分类，但始终手选；证据见 [验证记录](../Tests/project-installer-discovery/README.md)。

当前布局更新：磁盘从清理中心移至 Tools 下方的侧栏底部，显示硬盘图标和“磁盘空间”标题、容量条及可用空间；统一使用独立 DiskCapacityMonitor 的读取、错误与自动刷新状态，只由侧栏订阅，不向 AppModel 转发变更。侧栏和清理中心底栏共用 SidebarSurface 的不透明系统底色，跟随系统外观，避免桌面透色差异；其它维度底栏继续使用原 bar 背景。见[实施计划](dashboard-sidebar-footer-plan.md)和[逐文件验证](../Tests/dashboard-sidebar-footer/README.md)。


本轮项目选择策略见 [实施计划](project-selection-preferences-plan.md) 和 [逐文件验证记录](../Tests/project-selection-preferences/README.md)。设置切换即时更新既有结果和首页缓存，关闭仅撤销自动选择，不清空人工决定；扫描或执行期间禁用开关。Git 跟踪 DMG 使用同一手选快照边界，仍检查路径、权限、云盘、包和保护；不加入自动副本保留证明。未知 Git 状态与其它保护继续执行复验。


关闭/退出现行规则见 [关闭提醒选择计划](close-trash-reminder-choice-plan.md) 与 [原生回归](../Tests/close-trash-reminder-choice/README.md)：同工厂/执行器、关闭独有“不再提醒”，扫描中提示与删除资格独立；抑制只改偏好，成功才确认当前字节。退出等待、错误、终止后去重与设置恢复保持。

应用卸载性能必须测冷缓存首次进入，不能先取全量计划再计时。行级分析仅准备当前应用；空文件/receipt 选择汇总直接零；无选择的运行状态刷新不准备全表。批量保护只复用本批保护根解析，候选物理路径与执行复验保持，批量/单项等价与目标变化回归必须通过。证据和逐文件理由见 [本批验证](../Tests/application-first-entry/README.md)。
# 0.4.27 增量验证

维度扫描提示使用 `ModuleProgressView`，禁止复制一套不同的扫描空态；文案按本模块状态，不能只检查全局 isScanRunning。导航自检覆盖六模块 waiting/scanning、全部终态、缺失状态、旧报告及停止扫描。

关闭提醒通过会话级 Controller 保留繁忙期间的请求；不要在失效视图内轮询，也不要替换原生窗口 delegate。`zsh Tests/exact-trash-dialog/run-native-check.sh` 使用真实红色关闭按钮及受控模型，验证延迟记账、重复关闭、空清理与原两按钮确认；执行器禁止调用 Finder。完整命令与逐文件理由见 [验证记录](../Tests/module-progress-trash-reminder/README.md)。无新增依赖，不创建 requirements.txt。
# 0.4.28：退出回归

不得把可选清空任务的 Bool 当作用户退出许可。`--trash-emptying-self-check` 覆盖 Cancel 后退出、清空成功/失败均等待容量后退出、重复请求只执行一次；`zsh Tests/quit-without-emptying/run-native-check.sh` 原样提取生产 delegate，复用既有取消确认夹具，实际调用 NSApplication.terminate，必须收到 willTerminate 且进程结束。清空执行器禁止被调用。

同时运行既有真实红色关闭回归，确保关闭窗口的 Cancel 仍仅取消清空并保留后台会话。无新增依赖；逐文件理由和证据见 [本轮记录](../Tests/quit-without-emptying/README.md)。
# 0.4.30：扫描中清空回归

关闭、手动清空与明确退出共用工厂和执行器，只有关闭提醒显示“不再提醒”。扫描不能禁用清空按钮；取得同一清空锁后才显示可执行的确认，不保留禁用能力参数。不要因勾选抑制而伪造清空成功，设置恢复只改同一偏好 key。

`--trash-emptying-self-check` 覆盖扫描中两个入口×成功/失败，在模拟清空挂起期间用真实进度接收方法更新事件，验证 token、扫描状态、去重、容量刷新与统计。原生夹具检查显示的 NSAlert 清空按钮始终 enabled；不再提醒和退出回归保留。并发模拟不冒充真实扫描/Finder 执行，见 [验证记录](../Tests/trash-during-scan/README.md)。


本次普通构建分配 0.5.17（162），351 项 Release 测试、核心契约、签名和打包自检通过，已替换安装并打开。下一次普通构建自动分配 0.5.18（163）。本轮直接安装 App，不生成新 DMG；记录见 [当前版本说明](release-0.5.17.md)。


模型/项目条目不再提供展开入口、状态或按钮区，Finder 与永久保护统一使用既有原生右键菜单；主行限制原因继续展示。修改展示不得删减 Core 的验证证据。实施与验收见 [现行架构](architecture.md)。

首次进入验收还须覆盖真实内嵌 Helper 的图标渲染，模型数据基准或普通顶层应用图标不能代替。运行 `zsh Tests/application-first-render/run-icon-check.sh "$PWD/Sources/CleanerApp/ApplicationIconView.swift"`，150ms 预算测量实际 SwiftUI 图标布局；缺少本机 WorkBuddy 夹具返回 77，不算通过。图标语义继续执行 `zsh Tests/application-icons/run-check.sh`，覆盖专用图标、最近外层及非标准 APPL 目录。见 [现行架构](architecture.md)。

偶发切回卡顿按 [Helper 激活审计](helper-activation-audit.md) 取样：记录是否真实启用/授权、当前页面、采样时段，区分 MainActor 等待、后台注册查询与 SwiftUI 重算。按 Helper 文档中的原生 sample 命令只读捕获五秒，不注册 Helper 或请求权限；非事发采样和独立探针不能冒充卡顿复现。

容量在应用激活及每 60 秒刷新，既有操作生命周期刷新保持。文件系统读取必须离开 MainActor，同一时刻只允许一个请求；独立容量状态只通知侧栏，同值不发布。回归覆盖慢读取、重复请求、错误恢复、计时器释放和 AppModel 不受容量通知影响；清空垃圾桶仍等待操作后的容量读取。

项目产物回归必须覆盖运行中和活动未知均可选择、实时活动恒为 true 仍可隔离恢复，以及保护路径/凭据/重复文件保留规则继续生效。不得仅放开 UI 而让执行阶段继续拒绝；不得删除其它来源所需的共享探针。见 [项目活动策略回归源码](../Tests/CleanerCoreTests/ProjectArtifactActivityTests.swift)。

项目产物公钥回归需覆盖可选择、执行隔离与恢复，混合公私钥/格式不明/超预算 PEM 和真实凭据拒绝；SwiftPM 依赖例外须同时验证工作区记录、remote sourceControlCheckout 状态及根范围，不能仅按路径名放开所有 `.git`。见 [公钥与依赖回归源码](../Tests/CleanerCoreTests/ProjectArtifactPublicKeyTests.swift)。

项目目录/DMG 展示去重须验证：父目录取消后无隐藏安装包留在计划，根目录及相似前缀兄弟路径不误隐藏，受保护父目录仍有单项安装包，原始项目归属不回流大文件；目录消失后的跨模块迁移继承勾选与撤选。见 [目录去重回归源码](../Tests/CleanerCoreTests/ProjectArtifactPresentationTests.swift)。

容量变化指标已撤回；不得保留无展示用途的基准、差值或专用测试夹具。继续验证 statfs 快照、读取失败和既有扫描/清理/恢复/清空后的容量更新，并覆盖每分钟与应用激活读取；容量状态独立通知侧栏。见 [容量读取源码](../Sources/CleanerCore/DiskCapacitySnapshot.swift)。

回归测试保留可运行源码；本机输出、采样和一次性验证材料统一写入已忽略的 `Tests/temporary/`，不随源码分发。构建产物仅保留当前版本 DMG，App 目录和编译缓存沿现有忽略规则处理。

系统清理先展示统一的建议清理（默认展开）/深度清理 Deep Cleanup（默认折叠，仅原建议保留组更名），组内直接并列 System 和具体应用，沿用 cleanupApplication 的既有归属，不增加 Applications 父组，禁止靠目录名猜测归属；推荐资格修改须由历史依据与混合数据回归共同验证。回归文件为 [容量测试](../Tests/CleanerAppTests/DiskCapacityRefreshTests.swift) 和 [分组测试](../Tests/CleanerCoreTests/SystemCleanupApplicationGroupTests.swift)，执行 `swift test` 同时运行 CleanerCoreTests / CleanerAppTests。无新增依赖，Swift 项目不创建 requirements.txt。

系统清理已追溯到 0.3.35 的统一手动选择变更：恢复 0.3.30 普通应用缓存与日志的推荐资格，保留共享缓存、离线内容及微信聊天文件的手动限制。两级分组为建议清理/保留 → System/具体应用，默认展开清理、折叠保留。历史依据与回归验证见 [修复记录](disk-refresh-system-groups.md)。
