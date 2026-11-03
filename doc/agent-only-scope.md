# 已授权改动范围审计

## 范围修正

GitHub基线为origin/main `75c9c262b46ae41e3e99daef6fb0d0225056885c`。0.2.24把“未要求的部分不变”误解为仅保留Agent变更，撤销了用户此前明确要求的界面和扫描控制；此解释已被用户纠正。本批0.2.25（58）恢复这些要求，并继续保留Agent能力分析。

允许的范围是：Agent界面/功能；标题栏和侧栏边缘对齐；扫描时首页介绍、四范围和三项能力布局保持；四行始终可导航；四模块独立取消和继续扫描；以及必要的依赖、打包、版本、文档。未授权的其他扫描算法、清理规则、文件恢复、CLI契约和发布门禁保持远端。

## 本批逐文件审阅

| 文件 | 修改与必要性 |
|---|---|
| Sources/CleanerApp/DashboardView.swift | 首页始终挂载介绍、范围和能力区；范围行始终导航，右侧预留状态/取消/继续空间。保留清理失败项和重试入口。避免渐进扫描切换页面结构或操作按钮触发导航。 |
| Sources/CleanerApp/AppModel.swift | 四个模块分别持有任务和单次运行令牌，所有结果/进度先校验令牌及generation。取消只停止本模块；继续扫描复用同批其他结果，等待阶段可取消/恢复等待。模块结果直接合并到当前不可变报告，替代原整批汇总辅助结构。Agent推理归属于Agent任务取消范围。 |
| Sources/CleanerApp/Components.swift | 目的页底栏的取消绑定当前模块，并在取消后提供继续入口；原删除/执行控制保留。 |
| Sources/CleanerApp/ContentView.swift | 移除侧栏独立窗口标题，将应用标题和可见工具栏背景交由统一布局承载。 |
| Sources/CleanerApp/CleanerApp.swift | 使用系统unified工具栏，避免标题栏/侧栏分隔边界错位；不添加固定像素侧栏偏移。 |
| Sources/CleanerCore/SystemScanCoordinator.swift | 接受指定模块集合及共享generation，以独立任务运行原扫描器。四个原扫描分支语句不变；默认全量调用仍沿用原isCommitEligible报告条件。 |
| Sources/CleanerCore/SystemScanReport.swift | 增加仅替换模块状态的不可变报告方法，保留所有已扫描数据；取消/继续不丢失其他模块结果。 |
| 双语Localizable.strings | 仅新增继续扫描与部分取消提示，保持中英文占位符一致。 |
| AGENTS.md、README.md、docs/architecture.md、docs/development.md、doc/分析设计/计划及本文件 | 纠正授权边界，记录实际取消/继续语义和保留范围，避免再次误回退明确要求。 |
| Version.json | 本批仅patch递增一次到0.2.25（58）。 |

既有Agent改动继续保留：AgentEnvironmentView、AppInfrastructure、PermissionsView、SkillCatalog、AgentOverlapAI、AgentInference和Core Agent分析文件；根Package.swift、模型打包/校验脚本及许可均沿用Agent接入。本批未修改覆盖算法、阈值或缓存策略。

## 静态核对证据

- 相对本批开始快照，AppModel已有116个方法保持原文；8个原有方法修改仅用于开始/取消/完成/刷新、规则失效和导航。移除2个仅服务旧整批汇总的辅助方法，新增独立模块调度方法。Agent分析方法保持原文。
- 剥离指定模块参数、条件调度及单模块返回分支后，SystemScanCoordinator与远端原有扫描语句归一化一致，默认完整扫描的提交条件不变。
- 系统清理、应用、大文件扫描器，HistoryView文件恢复页、CLI只读契约、发布脚本/生产签名门禁/create-dmg脚本、AppInfo.plist及根Package.resolved与远端逐字节一致。
- 继续扫描是重新运行被取消的单个模块，保留其他模块结果；不宣称支持文件系统目录游标断点续扫。等待阶段取消不影响其他模块启动，旧任务回调不能覆盖继续扫描的新任务。

## 验证与产物

- CleanerApp Debug及最终Release构建通过；Helper、CLI、AgentInference均已构建并重新组装进App。998条双语文案、占位符和源码覆盖检查通过；git diff --check通过。
- 版本0.2.25（58）在主App/Helper元数据一致，设置页仍读取同一版本来源；本批只递增patch一次。
- [本地App](../build/SuperCleaner.app)与[DMG](../build/SuperCleaner-0.2.25-58.dmg)已完成重建；镜像校验有效。只读挂载后全部114个App文件以及符号链接与本地App一致，Applications快捷方式有效；codesign深度严格全架构核对通过，核对后已卸载镜像。
- 实际Mach-O部署目标：主应用、Helper、CLI保持macOS13.0，独立AgentInference为macOS14.0；主应用未直接链接Gemma/llama运行库。
- 模型大小309855456字节，SHA-256为`2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135`，模型LICENSE/NOTICE和SDK许可齐全。
- DMG大小299232416字节，SHA-256为`a1224148f0ae09679ca5609f7909beca7b71d0301809d547ad778e7d2e2d34fb`。
- 按项目要求没有新增或运行测试套件，没有提交或推送，没有写入用户Agent索引或执行文件清理。未完成完整GUI交互与旧系统实机验收；源码、编译和包一致性核对不代表这些验收。签名为本地ad-hoc开发签名。本轮临时材料交付前清理。

## 自审与必要工作评分

- 局部：导航与行内操作独立，100/100；否则取消会被导航截获，已实施。
- 全局：模块分别拥有任务和失效令牌，100/100；只改按钮无法解决联动取消和旧回调覆盖，已实施。
- 布局：使用原生统一工具栏及固定的状态预留空间，95/100；避免依赖窗口宽度的偏移补丁，已实施。

这些均为本次授权所需工作；未自动启动额外优化。

## 应用卸载筛选栏对齐（0.2.26 / 59）

用户授权：应用卸载页截图红框中的搜索/筛选区域，与大文件页对应区域保持位置、高度一致。

- `Sources/CleanerApp/ApplicationsView.swift`：标题间距从6改为5，与大文件页一致；筛选栏采用caption字号，并通过`fixedSize(horizontal: false, vertical: true)`使用内容固有高度。原有18/10内边距保持不变；没有调整搜索、分段筛选、排序、计数和刷新行为。
- `AGENTS.md`：记录以大文件页为筛选栏布局基准的偏好。
- `README.md`：补充用户可见的紧凑布局说明。
- `docs/architecture.md`、`docs/development.md`：在现有架构与开发文档中记录布局参数、垂直伸展约束及源码路径，避免为本次小改动搬迁全套文档。
- `Version.json`：本批次仅递增一次，从0.2.25（58）到0.2.26（59）。
- 本审计文件：记录本次授权、逐文件修改理由与验证限制。没有依赖变更；项目为Swift，未新增Python包或requirements.txt。

验证：`swift build --product CleanerApp`通过。未运行测试套件、未提交或推送；未重建App/DMG或替换运行中的应用，因此现有安装包仍为上一批版本，未完成实际窗口视觉验收。项目指定的`.trae/rules/project_rules.md`不存在，按AGENTS.md已有规范执行。

自审：两页的原有内边距已经一致，仅调内边距不能消除控件垂直伸展；按固有高度约束（局部价值95/100）和统一标题间距/字号（局部价值90/100）属于当前任务，均已实施。不使用固定高度硬裁切，不改共享AppModel或其他页面；暂无证据充分且需要继续实施的全局修改。

## 应用分析成功徽标简化（0.2.27 / 60）

- `Sources/CleanerApp/ApplicationsView.swift`：仅在分析状态不是complete时构造行尾徽标，去除重复的Basic analysis finished；保留受限、不可用、保护与等待状态。没有改变分析、预选、删除或权限逻辑，上一批筛选栏修改保留。
- `AGENTS.md`：记录正常完成不展示徽标的偏好。
- `README.md`：说明用户可见的状态徽标行为。
- `docs/architecture.md`、`docs/development.md`：记录展示层条件与保留底层状态的边界。
- `Version.json`：本批仅递增一次至0.2.27（60）。本审计文件记录范围与核对结果。无依赖变更。

只读调查：PermissionScanStartPolicy始终允许开始扫描；ScanPermissionPreflight依次尝试访问Documents/Desktop/Downloads，以便系统按需提示文件夹授权。设置页已有完全磁盘访问入口，App回到前台后重新检查。PermissionStatusService仅凭一个保护目录可读便标记granted，不能证明所有扫描路径可读；本轮未读取实际扫描报告，无法确定截图中的受限路径或原因。

自审：隐藏正常完成徽标属于明确授权的必要局部修改（95/100），已实施。按实际失败原因展示路径、区分权限/扫描边界并提供对应操作，是后续全局改善建议（95/100）；权限问题本轮为解释性调查，未自动改变授权流程或把受限结果伪装成完成。

验证：CleanerApp编译结果见本轮记录；未运行测试、未提交/推送、未重建App/DMG或替换当前运行实例，GUI视觉效果未实机验收。没有引入临时文件或Python依赖。

## 集中权限配置（0.2.28 / 61）

授权：用户要求优先通过集中授权解决可授权的扫描访问问题，在设置页统一配置或首次打开App时弹窗；不新增逐路径原因/解决入口。

逐文件核对（与本轮开始前快照比较）：
- `Sources/CleanerApp/AppModel.swift`：新增配置窗口、检查忙碌状态；bootstrap完成后按setupReviewed标记首次展示；新增文件夹系统设置跳转、标准文件夹请求/权限复查和关闭方法。既有扫描、清理、模块令牌及Agent分析函数保持本轮前原文。
- `Sources/CleanerApp/ContentView.swift`：新增集中配置sheet，显式稍后/继续关闭，不干扰已有删除sheet。
- `Sources/CleanerApp/PermissionsView.swift`：提取共享PermissionAccessSection供设置页和新窗口复用；统一完全磁盘访问、标准文件夹请求、App管理与可选Helper；返回后沿用前台刷新，继续按钮显式重扫。Helper复用原有注册、批准与会话授权，不自动提权。
- `Sources/CleanerCore/PermissionStatus.swift`：可读探测与失败共存时不再报告全部可用；只忽略明确不存在错误，避免权限阻止fileExists也被误认成不存在；成功文案只描述实际探测。已有错误处理用于将预期拒绝呈现为权限状态，没有新增隐藏异常处理。没有修改扫描数量/深度上限。
- `Resources/AppInfo.plist`：补齐Desktop/Documents/Downloads的系统授权用途说明，不加入无关权限。
- 两个`Localizable.strings`：新增12条对应中英文文案，保持键和占位符一致。
- `AGENTS.md`：记录集中配置、已查看不等于已授权的偏好。
- `README.md`：新增用户配置与重扫说明。
- `docs/architecture.md`、`docs/development.md`：更新现有架构、状态生命周期和权限边界；没有搬迁不相关文档。
- `Version.json`：本批仅递增一次至0.2.28（61）。本审计文件记录授权和验证。依赖不变，无需新增requirements.txt。

验证：最终CleanerApp编译通过；1010条中英文文案及占位符/源码覆盖检查通过；AppInfo.plist格式检查与git diff --check通过。编译曾显示ApplicationUpdateModel.swift原有的弱引用捕获警告，与本批无关。未运行测试套件或交互授权验收；未读取实际受限路径扫描报告，不声称本机全部访问问题已消除。未执行打包脚本（其中会运行测试），未替换App/DMG或当前运行实例；现有包仍是旧版本，不声称包版本已同步。没有提交/推送。指定的.trae/rules/project_rules.md仍不存在，遵循已有AGENTS.md约束。

自审与必要工作：局部修正混合成功/失败探测（98/100），全局统一首次/设置权限入口（95/100），补充实际系统提示用途说明（95/100），均在当前授权内并已实施。缺少完全磁盘访问可引导用户授予，但普通文件权限、系统保护、扫描边界、临时签名导致的授权失效不能通过一组开关全部消除；未据此扩大到扫描算法、修改文件权限或发布签名改造。无其他需要继续实施的范围内建议。

## 权限跳过与取消扫描数量上限（0.2.29 / 62）

授权：扫描遇到已确认的权限拒绝/系统保护拒绝时静默跳过，不显示区域权限不足；用户随后要求去掉扫描数量上限。本轮按App四模块及应用刷新落实，不改变CLI/删除前复验策略，不移除深度、耗时或字节读取边界。

逐文件核对与必要性：
- `Sources/CleanerApp/ScanAccessTracking.swift`（新增）：观察现有文件系统读取并记录OS权限拒绝，不增加内容读取、不改变原始异常或清理资格；统一计算可访问范围的GUI状态。普通I/O错误、配置故障、取消与其他边界不一并隐藏。
- `Sources/CleanerApp/AppModel.swift`：为每个模块运行创建独立访问记录，受原有运行令牌保护；渐进结果和最终状态使用同一展示结果。应用刷新、运行观察结果安装也复用规则；被拒绝读取的应用本体不进入可见列表，计数同源。App扫描上下文关闭固定条目计数限制；完成文案改为可访问范围，避免把其他失败误称为权限限制。
- `Sources/CleanerApp/ApplicationsView.swift`：仅因已确认访问跳过而受限的行不显示警告与逐路径限制；保留原始计划、估算大小标识、系统保护和非权限异常。
- `Sources/CleanerApp/DashboardView.swift`：移除单独的扫描前权限提示，沿用集中权限配置入口。
- `Sources/CleanerCore/Scanner.swift`：上下文增加enforcesEntryBudgets（默认true）；错误记录保留操作系统给出的失败路径，便于精确关联已记录的权限拒绝，不依赖文案猜测。
- `Sources/CleanerCore/ApplicationScanner.swift`：App扫描关闭应用发现、大小计数及挂载卷数量限制，其他调用保留原行为。
- `Sources/CleanerCore/AgentScanners.swift`：App扫描不因资产计数停止，保留深度和取消条件。
- `Sources/CleanerCore/DiskUsageScanner.swift`：App目录扫描不因条目计数停止，保留深度和取消条件。
- `Sources/CleanerCore/ApplicationCleanupScanner.swift`：App动态应用清理发现不截取固定数量的目录子项。
- `Sources/CleanerCore/CleanupRuleEngine.swift`：App规则发现和测量不执行条目计数上限；执行上下文保持默认受限策略，深度、保护和身份复验不变。
- `Sources/CleanerCore/ApplicationOwnershipGraph.swift`：App应用归属分析不因条目计数停止，保持时间边界、取消与归属保护。
- `Sources/CleanerCore/ApplicationInstallationInspector.swift`：App安装来源分析不受条目、卸载器候选或Steam根数量截断；仍保留时间/内容大小/签名判断。
- `Sources/CleanerCore/ApplicationDiagnosticScanner.swift`：App诊断文件扫描不受文件计数截断，读取字节和时间限制不变。
- `Sources/CleanerCore/HistoricalResidueScanner.swift`：App历史残留发现和测量不受条目数截断，补充循环取消检查，保护判断保留。
- `Sources/CleanerCore/InstallerDiscovery.swift`：App安装包遍历和测量不受条目数截断，深度、时间及格式验证保留。
- 两个`Localizable.strings`：新增两条可访问范围完成/其他未完成项的准确提示。
- `AGENTS.md`：记录静默跳过和App数量上限偏好及执行边界。
- `README.md`：说明用户可见扫描行为和仍保留的其他边界。
- `docs/architecture.md`、`docs/development.md`：记录读取观察、GUI状态投射、各扫描子流程的统一数量策略和删除前保护边界。
- `Version.json`：本批只递增一次至0.2.29（62）；本文件记录逐文件审计。没有新增依赖或requirements.txt。

自审：只隐藏文字而让其他模块最终覆盖状态不符合目标，因此逐个接通渐进/最终、刷新与观察安装入口（价值98/100，已实施）；直接删除原始覆盖记录会影响所有权判断，因此保留内部证据、只投射GUI（98/100，已实施）；仅删30,000/20,000/50,000三个入口数字仍会被内部计数截断，因此统一App上下文策略（95/100，已实施）。曾加入的应用大小预算额外提示在数量限制取消后不再必要，已撤回该修改。没有扩展到关闭SIP、修改目录权限、放开删除保护或取消其他读取限制。

验证：最终CleanerApp编译通过；1012条双语文案、源码覆盖和占位符检查通过；git diff --check通过。增量快照及git diff逐文件审阅完成，临时快照位于tests下并在交付前清理。按用户约定未运行测试套件；尚未进行真实权限拒绝/大目录GUI验收，不能声称在用户机器上所有受限提示均已实测消失。未重建App/DMG、未替换运行实例，现有安装包仍为旧版本；没有提交或推送。


## 按用户要求回退至0.2.29（62）

用户明确要求“回到0.2.29的版本”，本次撤销整个0.2.30批次，版本精确恢复0.2.29（62），不按普通修改规则额外递增。当前仓库含此前多个已授权批次的未提交修改，因此逐项回退本批增量，没有执行整仓reset/checkout。

逐文件说明：
- `AppModel.swift`：移除深入模式、模块深入范围记录、计划范围标记、目录按需加载/取消/迟到回写逻辑；恢复0.2.29的扫描入口、计划构建和模块上下文，保留原有独立扫描任务与访问跳过逻辑。
- `DashboardView.swift`：删除深入扫描按钮和新增说明，恢复单一开始扫描入口。
- `DiskUsageOutlineView.swift`、`DiskSpaceView.swift`：恢复原有展开已加载内容的行为，删除展开后继续扫描的交互、加载状态及相关文案。
- `DiskUsageScanner.swift`：移除子树扫描根、未加载扩展属性和子树合并API，并撤回0.2.30的深度边界兄弟遍历修复；仅保留0.2.29既有的App数量策略。
- `Scanner.swift`：移除expandsTraversal及范围复制方法；保留0.2.29的enforcesEntryBudgets和错误路径记录。
- `CleanupRuntime.swift`、`AppInfrastructure.swift`：撤销0.2.30的运行时范围/数量配置及标记复验改造，恢复0.2.29的复验行为。
- `ApplicationScanner.swift`、`AgentScanners.swift`、`CleanupRuleEngine.swift`、`HistoricalResidueScanner.swift`：撤销深入模式的深度绕过，保留此前数量上限取消策略及原有取消行为。
- `ApplicationOwnershipGraph.swift`、`ApplicationInstallationInspector.swift`、`InstallerDiscovery.swift`：恢复0.2.29的深度、整段耗时及单次操作限制，不保留手动深入模式。
- `ApplicationDiagnosticScanner.swift`、`FileSystem.swift`：恢复0.2.29的正文读取与解析；删除新增的`DiagnosticIdentityStream.swift`。`ScanAccessTracking.swift`删除分块读取代理，保留0.2.29权限跳过记录。
- 两个`Localizable.strings`：删除0.2.30新增六条文案，回到1012条。
- `Tests/coverage-implementation/`及`doc/scan-coverage-plan.md`：删除仅服务已撤销功能的定向验证和实施计划，避免无效代码、入口和文档残留。
- `README.md`、`docs/architecture.md`、`docs/development.md`：移除0.2.30使用/架构/开发说明，恢复0.2.29功能描述。
- `AGENTS.md`：记录保持简单界面、默认能力优先和暂缓手动深入扫描的最新偏好。本审计文件记录回退原因与范围。
- `Version.json`：依用户明确要求恢复0.2.29与build62，不再次递增。

自审：完整撤销人工交互相关功能及其底层支撑（100/100），保留0.2.29及此前已授权改动（100/100），均属本次必要工作。没有自动改成默认无限深度扫描，也没有启动额外优化。项目依赖未改变。验证结果以本轮最终记录为准；未打包或替换正在运行的App，未提交或推送。

回退最终验证：CleanerApp、CleanerHelper、supercleaner编译均通过；1012条双语文案/占位符及源码覆盖检查通过；git diff --check通过。代码中已无0.2.30深入模式、按需加载、范围标记及分块诊断解析引用；FileSystem/CleanupRuntime/DiskSpaceView/DiskUsageOutlineView恢复原文，其他文件保留0.2.29既有增量。临时回退快照已清理。

## Agent 覆盖排名/默认勾选修复与重新打包（0.2.30 / 63）

授权：用户报告看不到默认Selected的Skill及Top 5覆盖来源，要求解决并重建App和DMG。本批是0.2.29之后的新Agent修复，不恢复此前已撤销的深入扫描、目录按需加载或诊断分块解析。

定位证据：旧安装包仍为0.2.25（58）；本机旧索引843项/319747对与当前策略指纹不一致，真实分析入口抛出requiresFullRecalculation，而行内仅展示“尚未分析”，原因被藏在tooltip。排名和预选函数本身已有实现。

逐文件核对与必要性：
- `Sources/CleanerApp/AppModel.swift`：补充策略不兼容结束分支；清除旧排名和自动勾选，保留手动选择，直接给出既有设置重算说明。另在实际App验证中采样定位到runScan串行标准文件夹预检等待系统open，导致四模块尚未启动；按既有集中配置授权要求移除普通扫描预检，保留配置窗口的显式请求，启动文案同步。分析算法、阈值、清理执行与普通缓存策略不变。
- `Sources/CleanerApp/AgentEnvironmentView.swift`：列表上方直接显示现有分析状态；将已有行内覆盖组件移至独立文件，以便真实渲染验证。没有新增按钮。
- `Sources/CleanerApp/AgentContainmentLabel.swift`：保持原Top 5、路径和累计覆盖展示，仅将无结果时的隐藏提示改为直接可见的真实状态，并允许文字换行。
- 两个`Localizable.strings`：各增加一条策略不兼容说明；将旧版扫描必先请求权限的三条提示合并为两条准确状态，保持键与占位符一致，总计1012条。
- `Sources/CoreContractChecks/ReadOnlyInterfaceContract.swift`：标准打包检查首次因扫描真实宿主应用目录达到CLI预算而失败；改为复用已有隔离文件系统，仍断言完整状态、保护及只读性，没有调整生产扫描或降低断言。
- `Sources/CoreContractChecks/ReviewRegressionContract.swift`：仅将已有ReviewScanFileSystem从文件私有改为检查程序内可复用，避免复制测试文件系统。
- `Scripts/check-production-signing.sh`：标准打包第二次到达签名反向检查时，发现固定旧SwiftPM目录找不到新版Xcode生成的检查程序；使用SwiftPM报告的实际产物目录，仅修复工具定位，生产签名、身份、时间戳及更新检查规则不变。反向检查已验证完整配置通过后仍拒绝临时签名App。
- `Scripts/verify-app.sh`：校验规则资源时同时识别SwiftPM的平铺及Xcode标准macOS bundle布局，仍要求实际资源存在；新包通过完整签名、模型、双语设置与恢复检查。
- `Tests/agent-overlap-diagnosis/analysis-contract.swift`、`label-contract.swift`、`run-contract.sh`、`README.md`：保留真实Gemma夹具、生产组件渲染和复跑入口；材料只写Tests，不执行用户清理或连接MCP。其他临时诊断、全量索引、程序、日志和快照交付前清理。
- `AGENTS.md`：记录直接状态、简单界面及不沿用失效建议的要求。
- `README.md`、`docs/architecture.md`、`docs/development.md`：更新状态展示、预选条件及索引策略排查方式。
- `doc/agent-skill-overlap-analysis-design.md`：同步可见状态和本次明确授权的一次性索引重建，不改变普通扫描仅分析新增对象的约定。
- `doc/agent-overlap-repair-plan.md`：记录验收步骤、真实数据与交付结果；本文件记录授权和逐文件必要性。
- `Version.json`：本批仅递增一次至0.2.30（63）。无依赖变化，无需添加requirements.txt；指定的.trae/rules/project_rules.md仍不存在。

实际App阻塞修复仅移除启动前的主动请求，不授予权限或绕过受限读取；新增证据说明这是原先集中配置要求遗漏的必要入口，价值98/100。

本机修复：使用与App相同的扫描快照、Gemma及分析/预选函数，隔离重建1071项（1026个Skill、45个MCP配置）/526815对关系；941项有覆盖来源、428项达到当前阈值、926项具备清理资格。结合既有明确保留和覆盖来源保留规则，规划默认勾选213个Skill与4个MCP。完整索引回放新增0项、计算0对、未再次推理；校验Top 5不超过5项、排除自身且同类型后原子替换本机缓存。未修改用户手动保留配置，也未删除Skill/MCP文件。

自审：修复旧策略阻断及不可见状态（98/100）、重建真实索引和新包并验证预选（100/100）、修复宿主相关验证与打包工具定位（95/100）均为本次必要工作，已实施。未降低85%预选或0.95语义匹配阈值，没有增加手动深入操作或扩大到扫描/删除算法优化。所有建议均在当前任务内，无额外优化任务。

最终验证与交付：最终build-app.sh、verify-app.sh、create-dmg.sh全部通过；80项XCTest无失败，1012条双语文案检查及git diff --check通过。DMG逐文件SHA/符号链接与最终App完全一致，App/Helper资源/镜像版本均0.2.30（63），内置模型SHA与字节数正确；本地临时签名，未做生产公证或发布。App实机扫描四模块立即启动且大文件完成；Agent项目根发现的系统文件属性读取仍在等待，工具不允许操作系统权限窗口，已请求用户处理，整轮GUI排名/Selected筛选尚未计为通过。本机实际分析和预选、完整缓存回放、真实组件渲染均已通过。临时材料已清理，仅保留四个定向验证文件；新索引保留在应用支持目录。没有提交或推送。

## 清理中心行布局与中性扫描状态（0.2.31 / 64）

授权：用户指出首页仍显示橙色“部分完成”，要求移除右侧箭头和扫描时的Cancel Scan，状态最右对齐，四行悬停高亮与应用卸载一致。各模块内部已有取消/继续入口，保留其独立控制能力。实施计划见[清理中心布局](cleanup-center-layout-plan.md)。

逐文件核对与必要性：
- `Sources/CleanerApp/DashboardView.swift`：删除首页行尾箭头及Cancel/Resume按钮和100pt操作占位；状态保留150pt宽度并靠行最右侧。将原行内间距移入导航按钮以覆盖整行点击/悬停区域；新增hoveredModule，仅悬停时使用与ApplicationsView相同的Color.accentColor.opacity(0.08)，移出恢复。limited仅在首页映射为中性“扫描已结束”，不显示警告图标；失败、取消、成功与扫描中仍明确区分。未更改任何模块扫描、访问跳过、进度令牌、清理/恢复或CLI。
- 两个`Localizable.strings`：将仅用于首页的“部分完成”键替换为“扫描已结束”/“Scan finished”；不更改恢复记录的“删除操作部分完成”。双语总数仍1012条。
- `AGENTS.md`：用本次明确要求替换此前首页行内Cancel/Resume约定，记录右对齐、无箭头、模块页控制与共享悬停颜色。
- `README.md`：说明首页状态/导航、取消/继续所在位置及中性结束文案。
- `docs/architecture.md`：同步首页展示与内部数据分离，移除旧版“行内状态控制”的过时描述。
- `docs/development.md`：记录内部取消/继续入口不得丢失，以及首页文案不得篡改CLI/覆盖/删除保护。
- `doc/agent-overlap-repair-plan.md`：补录前一批Agent真实GUI验收：用户处理权限并手动重启后，实际显示1026个Skill、213个加入计划；Selected筛选画面可见勾选、Top 5名称/路径及累计覆盖。4个MCP仍标为本机规划验证，未冒称已逐项GUI核对。
- `doc/cleanup-center-layout-plan.md`：本批计划和验收结果。本文件记录逐文件必要性。`Tests/cleanup-center-layout`仅临时保存增量快照、打包日志及验证材料，交付前清理。
- `Version.json`：本批仅递增一次至0.2.31（64）。未新增依赖或requirements.txt，指定的.trae/rules/project_rules.md仍不存在。

入口核对：ContentView的四个模块均保留DimensionActionBar；Components.swift现有的应用分支及其他模块分支仍提供当前模块取消/继续。本批未编辑上述文件。清理中心行仍调用原openScanResult，等待/扫描/取消时仍可进入模块。

自审：局部移除重复控制并统一悬停（98/100）、中性展示而保留原始保护与CLI（95/100）均为当前明确任务的必要工作，已实施。没有为消除提示而放宽删除资格、伪造底层扫描完整性或移除执行复验；没有新增扫描操作或扩展算法优化。无其他需要自动启动的工作。

最终验证：0.2.31（64）标准构建、App验证、DMG脚本全部通过；80项XCTest无失败，1012条双语文案与git diff --check通过。实际首页已确认无箭头、无重复取消/继续、最右状态对齐及浅蓝悬停/移出恢复；系统清理和应用卸载实际显示Scan finished中性状态，大文件显示Scan complete。系统、应用、Agent内部取消入口实际可见，Agent内部取消及继续均已执行验证，其他模块结果保留，验证后已继续Agent扫描。大文件因快速完成，取消能力由共享底栏代码与既有模型自检核对，未声称捕获其扫描瞬间。DMG文件/符号链接与最终App逐项一致，版本及模型验证通过。临时材料已清理；没有提交或推送。

## 首页完成标记统一与三卡等高（0.2.32 / 65）

授权：用户要求右侧完成标记统一为大文件现有的绿色勾选Scan complete，底部三卡一样高，左侧以右侧较高卡片为基准。本批是上一批首页样式的明确调整，不扩展其他功能。

逐文件核对与必要性：
- `Sources/CleanerApp/DashboardView.swift`：移除limited单独的纯文字分支；completed/limited共用同一个“扫描完成”、checkmark.circle.fill和green映射，保证文字、图标、颜色完全一致。卡片容器固定自身固有高度，子卡片允许在该高度内扩展并顶部对齐，使单行说明与多行说明的背景等高；不硬编码高度，不添加测量回调、占位文字或依赖。
- 两个`Localizable.strings`：删除不再使用的独立“扫描已结束”键；复用已有“扫描完成”/“Scan complete”，其余含参数的扫描结束消息及恢复记录不变，双语共1011条。
- `AGENTS.md`：用最新要求替换上一批的中性limited文案约定，记录统一绿色勾选和按最高内容等高；明确取消/失败/扫描中仍分别展示。
- `README.md`：更新用户可见的完成标记及三卡等高说明。
- `docs/architecture.md`：同步展示映射与原生等高布局，继续明确原始状态、覆盖和清理资格不变。
- `docs/development.md`：记录共用完成样式、顶部对齐和不按当前语言行数写死高度的约束。
- `doc/cleanup-center-layout-plan.md`：保留0.2.31历史记录，追加本批目标和验收；本文件记录逐文件必要性。
- `Version.json`：本批仅递增一次至0.2.32（65）。未新增依赖，无需requirements.txt；指定的.trae/rules/project_rules.md仍不存在。临时材料仅在Tests/cleanup-center-consistency，交付前清理。

自审：共用已存在的大文件完成样式（100/100）、原生固有高度等高布局（98/100）均为当前明确任务的必要工作，已实施。没有更改AppModel、扫描算法、权限、取消/继续、Agent分析、清理/恢复、CLI或发布检查规则。没有提出或启动额外优化。

最终验证：0.2.32（65）构建、App验证与DMG脚本通过，80项XCTest无失败，1011条双语文案与git diff --check通过。实际新App英文画面中左卡一行说明、右侧两卡两行说明，三背景上下对齐且等高；完成状态通过同一case映射复用大文件样式并完成新包构建核对，本轮没有为展示调整重复整机扫描。App/Helper/镜像版本一致，镜像逐文件及符号链接与最终App一致，模型/签名/许可检查通过。临时材料已清理，没有提交或推送。

## 内嵌应用图标回退与覆盖安装（0.2.33 / 66）

授权：用户报告WorkBuddy Helper/GPU/Plugin/Renderer/Legacy Cleaner显示通用占位图，要求补全图标；沿用用户明确要求直接覆盖同一安装位置。计划见[图标回退](application-icon-fallback-plan.md)。

复现：本机这五个内嵌.app未声明独立图标，NSWorkspace返回图像与系统applicationBundle通用图标一致；主WorkBuddy和文件浏览器均有独立图标。真实共享缓存定向检查在修复前五项失败，独立图标/顶层图标保持检查通过。

逐文件核对与必要性：
- `Sources/CleanerApp/ApplicationIconView.swift`：仅在共享缓存中添加通用图标回退。保留NSWorkspace原生读取；图像确为系统通用图标时，沿真实Contents包路径和APPL元数据寻找最近的外层应用包，外层也通用时继续；无.app后缀的安装临时包按声明资源读取。当前图标非通用立即保留；无外层所属应用时返回原图。沿用原有缓存键和容量，不按WorkBuddy名字或Bundle ID前缀硬编码匹配，不下载图标，不修改应用包。缓存从文件私有改为模块内可见，以便定向检查直接调用生产实现；未增加公共接口或替代实现。
- `Tests/application-icons/icon-contract.swift`、`run-check.sh`：真实AppKit图标回归，五个缺图Helper应继承WorkBuddy；文件浏览器保持独立图标，其更深层Helper继承最近文件浏览器；顶层及无所属外层的通用图标保持原样。依赖本机WorkBuddy夹具，缺夹具返回77，不计为通过；额外在Tests内生成无.app后缀的安装包父目录，复现真实列表发现的安装临时目录情况，合计14项。编译产物、生成夹具和诊断快照交付前清理。
- `AGENTS.md`：记录原生图标优先、真实包关系回退，以及固定覆盖/Applications/SuperCleaner.app并从此启动的偏好。
- `README.md`：说明内嵌Helper图标和固定安装位置。
- `docs/architecture.md`：说明卸载页与系统清理页共享图标缓存及回退边界。
- `docs/development.md`：记录排查/定向验证命令，不得仅因缺某个plist字段就覆盖asset catalog或自定义图标；补充覆盖安装流程。
- `doc/application-icon-fallback-plan.md`：计划及验收。本文件记录逐文件必要性。
- `Version.json`：本批仅递增一次至0.2.33（66）。没有新增依赖，无需requirements.txt；指定的.trae/rules/project_rules.md仍不存在。

调用范围：ApplicationIconView仅在ApplicationsView及GuidedCleanupView原有位置使用，本轮两个调用者及AppModel均未编辑。未更改扫描算法、应用发现/归属、卸载项目或清理/恢复保护，也没有修改目标应用图标资源。

自审：共享入口修复通用图标（98/100）、最近真实包关系回退且保留已有图标（98/100）、验证新包后固定位置覆盖（100/100）均在当前明确授权内，已实施。未扩展为按厂商或Bundle ID猜测图标、网络下载或新的图标配置界面。无额外优化任务。

最终包验证：本批标准构建中80项XCTest无失败；真实列表补充发现无.app后缀的安装临时包后，只重建受影响的CleanerApp并重新签名，未重复运行未改动的Core测试。最终生产实现14项定向图标检查通过，App结构/签名/模型/许可/清理恢复烟测及生产签名负向门禁通过，1011条双语文案与git diff --check通过。App与Helper均为0.2.33（66）；最终build、/Applications安装副本及DMG内App逐文件SHA-256和符号链接完全一致。DMG SHA-256：`cd48251db514379db5c9c5faccc768d146ba8ecd64ff62dfcb49db0c7ce9a324`。

实际界面：从固定安装位置启动并完成应用扫描，WorkBuddy筛选列表中Helper/GPU/Plugin/Renderer均为WorkBuddy图标，File Browser保持独立图标。Legacy Cleaner本次以14项中的真实包和非标准外层夹具检查验证，滚动时窗口不可用，未声称单独截取其界面。临时材料清理，仅保留两份定向检查源码；未提交或推送。

## 共享源保留、缓存预选、Top 3及卸载栏高度（0.2.34 / 67）

授权：用户要求优先保留全局共享资源、缓存不依赖重叠预选、Top 5改Top 3，并追加指出卸载页筛选栏仍过高，要求与大文件页一致。计划见[本批计划](agent-selection-priority-plan.md)。核对官方说明及本机链接后，明确.agents不是所有Agent自动加载的MCP/Skill注册表，保留必要软链接入口，不修改Agent配置。

逐文件必要性：
- Sources/CleanerCore/AgentOverlapAnalyzer.swift：展示名单仅保留Top 3，累计并集仍完整；规划接收缓存对象集合，先以基线资格/明确保留筛选缓存，再计算其他重复项；待删缓存不能提供覆盖，已保留来源足以达到阈值时优先使用，保留其余必需覆盖来源。不变更模型、包含参数、向量和索引格式，无须全量重算。
- Sources/CleanerApp/AppModel.swift：仅Agent选择链路中按注入home的.agents/、.cache/路径边界标记共享保留/缓存预选；原Skill绑定/MCP清理资格保留。无索引、无模型及策略失效时缓存仍可独立预选；扫描完成统一应用，用户明确取消优先。共享源的手动选择仍由用户决定。未改系统清理默认项、应用卸载/恢复及扫描算法。
- Sources/CleanerApp/AgentContainmentLabel.swift及两个Localizable.strings：同步Top 3标题和说明，累计仍来自所有同类来源。
- Sources/CleanerApp/ApplicationsView.swift：将原先整行fixedSize移至segmented Picker，保持原18/10内边距、caption字号和筛选行为；不写死高度、不改大文件页。
- Tests/agent-overlap-diagnosis的analysis-contract.swift、label-contract.swift、run-contract.sh、README.md：更新Top 3断言与输出文件，补充缓存无关系预选、资格/明确保留和待删缓存不支撑删除等生产规划检查源码；本批未运行测试。
- AGENTS.md、README.md、docs/architecture.md、docs/development.md、doc/agent-skill-overlap-analysis-design.md及计划：同步精确路径边界、共享并非自动加载、Top 3、缓存与覆盖来源约束，以及筛选栏必须在Picker自身约束。本文件记录逐文件审计。
- Version.json：同一未完成批次一次递增到0.2.34（67），追加筛选栏修正不再次递增。无依赖变化，requirements.txt无需新增；.trae/rules/project_rules.md仍缺失。

自审：共享保留和支持源选择98/100、缓存独立预选且不放宽资格95/100、Top 3展示100/100、Picker自身尺寸修正98/100，均在本批用户授权内。未按文件名删除全部cache，未处理用户凭据或修改软链接，没有实际删除。

追加用户要求（同一未完成0.2.34批次）：
- ContentView.swift：工具栏背景可见性移动到整个NavigationSplitView，避免仅详情列配置；继续使用系统统一工具栏与侧栏布局，不加固定宽度偏移。实际边界仍待核对。
- AppModel.swift、PermissionsView.swift：全扫描先展示集中权限配置，移除启动时setupReviewed一次性入口；配置窗口.task依次请求标准文件夹并复查权限，用户确认后通过独立continue方法进入实际扫描，避免startFullScan再次打开窗口。未完全授权时按钮明确“继续扫描可访问位置”；App管理/Helper仍遵守真实操作和显式授权边界，不虚构预先验证。设置页保留补充入口，操作本身不会由代理代替用户批准。
- 两个Localizable.strings：新增扫描前权限标题、说明、完成后开始扫描按钮；共1014条双语检查通过。
- 实机复核证明，仅把fixedSize改到Picker但保留水平弹性仍未压缩栏高；继续改为隐藏Picker标签并使用完整固有尺寸，再作实际验收。不能把此前源码层约束视为已解决。

继续跟进本批用户反馈：
- PermissionStatus.swift：新增requestScanAccess，复用原标准文件夹预请求，再复用应用关联路径与Agent路径注册表串行访问目录；应用数据根下两层入口提前访问以触发应用数据授权。只查询目录/文件身份与目录名称，不读取文件正文，不修改权限、配置或数据；取消及时退出，访问失败保持既有跳过语义。原requestStandardFolderAccess及CLI行为不变。
- AgentScanners.swift：以路径注册表scope优先，修正用户主目录全局Skill被项目遍历误标为Project的问题；ID仍为真实独立路径，不按同名合并，资格与保护不变。
- AgentContainmentLabel.swift：改为Grid统一比例列，路径行跨列，避免第三个比例因文本长度错位。
- SidebarToolbarAlignment.swift（新增）与ContentView.swift：公开AppKit跟踪分隔符绑定真实NSSplitView，透明标题栏让分栏背景连续，不加固定偏移；工具栏诊断只记录控件类型/几何信息，临时记录代码已移除，材料交付前清理。
- 实机已核对Top 3、独立缓存预选（包括未提取描述对象）以及Codex分组685项；截图中的其他来源不是未扫描，而是分组和筛选使其不在当前可见区域。recommendations仅接受本轮activeIDs，两端对象都属于当前清单。没有新增重复占位条目或改写已有清单身份。

最终收口（替代本批中间“可访问位置继续”入口）：用户再次要求全部授权前置后，全扫描继续入口增加本轮预检完成标记及当前App完全磁盘访问探测granted条件；打开配置窗口即清除该标记，避免旧快照造成首帧竞态。配置期外不再主动探测保护目录；App管理观察结果从真实回执更新已知快照，不额外读取保护目录。系统设置深链提升为PermissionStatusService的共享常量，未进行探测时仍能打开设置。新增对应状态说明后共1016条双语文案。

标题栏最终取舍：临时几何记录显示系统已有NSTrackingSeparatorToolbarItem，真实分栏宽度238pt且已跟踪正确；单独背景造成上部可见缺口。最终仅保留SidebarToolbarAlignment的透明标题栏桥接与整窗隐藏额外工具栏背景，删除冗余分隔符重绑/插入及诊断代码。实机顶部到底部边界已连续，不使用固定偏移。

交付构建核对：CleanerApp/Helper/CLI release编译、定向检查源码类型核对、1016条双语与git diff --check、代码签名完整性通过；未运行测试套件。build、固定安装App及DMG内App的123个文件/符号链接逐项一致，App/Helper均0.2.34（67）。最终DMG SHA-256：`aadec9548eb649e11454e2c349084d06e503caa8c30d71c183e0e2f7cde60443`。用户已授权重启并恢复主窗口，实际完全磁盘访问显示可用，已开始最终只读扫描。临时备份和初版镜像/诊断材料已清理，系统未接受旧备份注销，未重置全局注册库。没有提交或推送。

最终实机核对已完成：在同一最终安装包中，大文件和卸载页标题均正常左对齐，筛选栏上下边界一致（本机2倍截图约306–390 px），筛选控件未重叠；标题栏分栏边界全高度连续。用户授权后完全磁盘访问显示可用，配置确认后扫描，系统默认清理恢复至767项/15.92 GB，大文件57项/30.75 GB。随后Agent完成（1026项），三项比例包括1.9%/2.2%均右对齐；共享源User/Shared标签、缓存预选和Trae分组中的archify独立条目已实机确认。


同一批次继续跟进工具栏切换录像及Agent行空间要求：
- `ApplicationsView.swift`：搜索框固定260 pt，排序和计数各固定140 pt，分段固定420 pt；用ViewThatFits只按可用宽度选择单/双行，不因选项或数量重排；删除Refresh Apps按钮。用户录像三帧显示搜索框右边界由约1104 px收缩到912 px，不能把单张初始等高截图作为切换稳定性的证据。
- `ApplicationScopePicker.swift`（新增）：原生NSSegmentedControl采用fillEqually、固定分配宽度及small字号，由同一Binding切换现有ApplicationListScope；避免SwiftUI segmented Picker在当前系统中随选择改变内部尺寸。只桥接此现有控件，不改过滤算法或新增操作。
- `AgentEnvironmentView.swift`：Skill及MCP均改为顶部对齐的左右两栏，当前对象的全部原有信息在左栏连续排布，右栏只放Top 3；保留原复选框、资格、路径身份、分组和虚拟化列表。
- `AgentContainmentLabel.swift`与两份Localizable.strings：移除Combined Coverage整行及不再使用的两份文案，不改变AgentOverlapAnalyzer中的累计位图、阈值或预选。百分比网格保留。
- `AGENTS.md`、`README.md`、`docs/architecture.md`、`docs/development.md`、分析设计及计划：更新固定搜索/分段宽度、窄窗换行、两栏信息和不显示累计行的约定，替代前面的Picker固有尺寸方案；没有更改依赖或再次递增版本。

必要性自审：固定搜索及分段/数量空间100分、原生等分控件96分、连续左右两栏与移除累计行100分，均为本批明确要求。此前仅处理纵向固有尺寸遗漏了反复切换时的宽度变化，本次以录像中的具体变化补齐验收；未附加扫描或清理算法优化。CleanerApp release重新编译通过（只保留既有ApplicationUpdateModel警告），1015条双语校验、签名与123项文件/链接一致性核对通过；未运行测试套件。

最新App/Helper仍为0.2.34（67），已覆盖固定安装位置，DMG已更新；新DMG SHA-256为`19c47769d466c2c3541a190e866b04dce8f695728b92114ca1dfc7e9b944bfd7`。重启后系统在扫描前标准文件夹open调用等待用户权限响应，已向用户说明本地重打包身份变化并请求处理；没有代为授权或开始删除。


用户处理授权后继续验收：
- 实机逐项切换All/Uninstallable/Running/System protected，搜索框边界均约516–1032 px（260 pt布局宽度，含原生边框），筛选段/排序/计数位置保持不变，Refresh Apps已移除。发现默认1042 pt详情宽中含末尾Spacer时总宽1044 pt，错误选择两行；`ApplicationsView.swift`仅删该Spacer并在外层填满可用宽，单行总宽1032 pt，仍保留真正窄窗的两行适配。
- 实机1026项Skill与45份MCP结果中，当前对象的标签、路径、数量/大小紧跟描述，右侧Top 3顶部对齐，Combined Coverage已消失。MCP长名称首行的100%未能在画面显示，虽存在于AX树仍不能算视觉通过；`AgentContainmentLabel.swift`进一步用普通HStack和固定50 pt比例列替换Grid，标题/路径minWidth为0并各自截断，避免跨度计算让比例越界。内部累计关系/阈值/预选无修改。
- 本批自审：单行宽度预算修正100分、固定比例列并允许名称收缩100分，均为用户要求的稳定布局验收所必需，无额外优化。重新编译通过，1015条文案与git diff --check通过，App/Helper版本0.2.34（67）；最终build、安装副本和DMG内123个文件/链接一致，DMG SHA-256：`a8dd697970a4a758cdd6da290de16384946632b3c68fe684c4acb80ca16ff4b6`。未运行测试套件。
- 最后两处修正重打包后，macOS实际探测再次要求完全磁盘访问，设置页面开关虽on仍未通过。已打开设置深链并交还用户关闭再开启，未操作权限开关、凭据或系统信任；最终包单行/长名称画面待该响应后继续。此前实机结论明确对应重打包前的同批界面，未把源码预算当作最终实机证明。


## 0.2.34（67）最终验收收口

用户再次处理当前包完全磁盘访问后，实际配置页显示Available，确认后正式扫描。最终安装包实机验收通过：
- 默认1280 pt窗口及恢复后的238 pt侧栏下，All/Uninstallable/Running/System protected分别显示94/22/10/65项，四次截图中搜索框两端均约516–1032 px，各控件位置、宽度不变；工具条约306–390 px，与同包大文件页一致，Refresh Apps不存在。
- 系统较窄窗口下使用两行，不重叠，搜索长度仍固定；切换可卸载与系统保护无几何变化。核对后恢复原窗口尺寸及238 pt侧栏，应用筛选保留可卸载。
- 当前1026个Skill与45份MCP配置加载1071项缓存关系；Skills三项比例同列右对齐。MCP长名称首行的100.0%在最终截图中完整显示，修复前仅AX可见而画面不可见的问题已消除。两栏顶部对齐，元数据紧随当前对象描述，Combined Coverage不显示。未更改或执行删除计划。
- 当前已授权安装副本就是最终交付包，不再修改二进制/重打包或重启。包签名、版本和123项文件/链接一致性核对沿用最终a8dd697970a4a758cdd6da290de16384946632b3c68fe684c4acb80ca16ff4b6镜像的已通过记录；此后仅完善本验收记录。未新增依赖、未运行测试套件、未提交或推送；无后续授权内必要修改，不另启动优化。

## Skill/MCP软链接排除与删除协作文件（0.2.35 / 68）

用户明确要求：软链接Skill/MCP不进入搜索清单、Top 3或后续分析；随后要求删除根目录AGENTS.md，并授权定向检查。计划见[本批计划](agent-symlink-exclusion-plan.md)。不更改其他模块、布局、模型、阈值、文件恢复或真实清理行为。

- `Sources/CleanerCore/AgentCatalogPathPolicy.swift`：复用不跟随链接的identity逐级核对路径，拒绝本体及父目录链接；身份不可验证时不加入清单，避免跟随目标读取。
- `Sources/CleanerCore/AgentScanners.swift`：在分类、清单与清理单元构造前跳过链接，并验证显式根目录父路径；不递归进入链接目标。
- `Sources/CleanerCore/SkillCatalog.swift`：入口核对Skill和manifest；查找manifest改用不跟随链接的身份检查，断链不再降格为无manifest的路径条目。真实目标及其中无关引用链接不受影响。
- `Sources/CleanerCore/MCPConfigurationCatalog.swift`：在读取配置前拒绝链接文件和链接父路径，不生成不可读占位清单。
- `Sources/CleanerCore/AgentOverlapAnalyzer.swift`：只补齐当前清单内对象缺失的同类关系；旧链接历史数据保留但不参与新配对。增加关系完整性判断，真实对象恢复时复用旧向量，防止只按“对象已知”漏掉缺失配对。
- `Sources/CleanerApp/AppModel.swift`：当前对象集合直接来自报告；报告变化立即刷新展示，防止旧Top 3在索引加载期间残留。快速复用分支同时检查关系完整性。
- `Tests/CleanerCoreTests/AgentSymlinkExclusionTests.swift`、`Tests/agent-symlink-exclusion/README.md`：新增真实文件系统及旧索引定向检查与证据；`Tests/CleanerCoreTests/AgentScannerTests.swift`、`Sources/CoreContractChecks/AgentScannerContract.swift`仅使已有虚拟文件系统正确返回已知条目的父目录身份，未放宽生产过滤。
- `AGENTS.md`：按用户要求删除，不重建。Git最早记录为73e65ba（2026-10-20，zhangrongxiang.kevin）；不能仅凭提交证明最初是否Codex生成。本会话扩写依据为用户此前“如果项目根目录下有AGENTS.md文件，更新其中Project workflow章节”要求，当前删除指令优先。`docs/development.md`删除现行维护引用，历史审计保留原发生事实。
- `README.md`、`docs/architecture.md`、`docs/development.md`、`doc/agent-skill-overlap-analysis-design.md`及本批计划：同步排除阶段、真实目标保留及当前清单/缓存边界。无新增依赖，requirements不变。

自审：入口统一排除100分、当前清单约束100分、恢复真实对象补齐关系98分、删除AGENTS.md 100分，均为当前已授权需求的必要修改；未扩大为缓存清空或Agent目录整理。指定`.trae/rules/project_rules.md`仍不存在。定向检查12项通过，未运行全量套件、未提交或推送；未删除任何用户Skill/MCP或链接。

最终交付：本批仅递增一次至0.2.35（68）。CleanerApp release编译通过；1015条双语检查及git diff --check通过；签名、模型长度/SHA与许可核对通过。复用上一版未变的推理运行时/Framework，更新本批编译的主程序、Helper、CLI及Core资源后由内向外重新签名，再运行create-dmg.sh；未运行含全量测试的build-app.sh/verify-app.sh，不把本批定向验证描述为全套发布门禁。

已退出旧实例并覆盖固定`/Applications/SuperCleaner.app`，未新增安装副本，设置及本机索引保留。App/Helper及DMG均0.2.35（68），三份123个文件/链接的SHA/链接目标一致；DMG SHA-256为`8a313463fc3a7283f906d0ee085a906315b1329b55b6ddd5ff0eef000d47812d`，证据见[包核对](../Tests/agent-symlink-exclusion/package-verification.txt)。本地开发签名，未公证或发布。实际启动固定安装副本并在设置页确认0.2.35 68，回到清理中心；未发起新一轮真实扫描或权限交互，因此本批过滤验收依据为授权的真实文件系统定向测试，未声称已完成当前用户目录的全扫描。AGENTS.md删除状态已再次确认。

## 清理中心全扫描用时（0.2.36 / 69）

用户要求在首页全扫描按钮右侧显示从开始至当前的整体用时，全部扫描结束停表。计划见[计时计划](full-scan-elapsed-plan.md)。

- `Sources/CleanerApp/AppModel.swift`：仅增加全扫描起止时间及会话标记；实际beginFullScan重置起点，四模块空闲及Agent分析完成后冻结。规则加载失败、全部取消的收口同样冻结；继续本轮取消模块沿用原起点。单模块刷新不重置或继续上一轮全扫描用时。未修改扫描任务、覆盖算法、权限与清理规则。
- `Sources/CleanerApp/DashboardView.swift`：按钮与计时文字放入同一行；计时区域180 pt，等宽数字HH:MM:SS，每秒仅更新局部TimelineView。未扫描时隐藏文字但预留位置，结束后静态显示，无后台秒级模型广播，不新增按钮。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：新增同一条用时占位文案，默认英文Elapsed，中文扫描用时。
- `README.md`、`docs/architecture.md`、`docs/development.md`、本批计划和本审计：记录开始/停止边界、取消/继续与布局约定。未重建AGENTS.md，未新增依赖。
- `Version.json`：本批仅递增一次至0.2.36（69）。

逐处自审：计时位置和局部秒级刷新100分、四模块及Agent分析共同收口100分、取消/失败/继续与单模块刷新边界98分，均为本次用时显示的必要工作，未启动其他优化。CleanerApp release编译通过；1016条双语文案及git diff --check通过；仅既有ApplicationUpdateModel.swift弱引用捕获警告。未运行测试套件；上一批软链接定向测试授权未扩大到本批。没有提交、推送或文件清理。

交付：更新主程序和Core文案资源、App/Helper版本元数据，复用其余未变运行时及Framework，重新签名后生成DMG；未运行含全量测试的打包/验证总脚本。已覆盖固定`/Applications/SuperCleaner.app`，实际进程路径与设置页确认0.2.36（69），返回清理中心。App、安装副本与DMG内123项文件/链接一致，模型长度/SHA及许可、签名均通过；DMG SHA-256为`da2344b7f8773a1e2422b812aeb2e635fc86f9a9265a99e07a1c756f81bd3443`，见[包核对](../Tests/full-scan-elapsed/package-verification.txt)。未发起新一轮真实扫描或授权提示，计时停止/恢复边界本批为源码生命周期审阅，未声称已完成真实全扫描的秒数实测。临时镜像已卸载，材料已清理；开发签名，未公证或发布。

## 权限界面、识别与固定签名（0.2.37 / 70）

用户要求移除设置的文件/文件夹授权区，并追加同时解决签名稳定性与权限识别；已明确选择“本机自签开发证书（仅本地使用，需本人确认系统信任）”。用户随后指出GitHub版DMG也可手动分发其他Mac，已纠正此前将手动安装和Apple公证发行混为一谈的说明。计划见[本批计划](permission-signing-repair-plan.md)。

- `Sources/CleanerApp/PermissionsView.swift`：删除共用权限区的文件夹说明/请求/设置按钮；设置及扫描前窗口同步简化。FDA访问拒绝显示“访问检查未通过”，未验证时说明仍可扫可访问位置；不再把granted作为开始按钮门槛。
- `Sources/CleanerApp/AppModel.swift`：删除失效的FilesAndFolders跳转，预检先加载当前访问结果，FDA可用时不重复请求标准文件夹；仍完成本轮预检才可开扫。移除完成配置时的强制granted判断，未改清理执行规则。
- `Sources/CleanerCore/PermissionStatus.swift`：仅验证用户TCC保护目录能否列举，不读取数据库。EPERM/EACCES/Cocoa明确访问拒绝与缺失/一般错误分别处理，其他App的数据目录失败不再参与FDA判定；预访问支持明确跳过标准文件夹。
- 两个`Localizable.strings`：删除失效授权区和旧判断文案，新增准确状态/解释。1012条双语及占位符校验通过。
- `Scripts/signing-identity.sh`：默认要求有效证书，优先固定指纹，不可用就失败；不静默换证书或退回ad-hoc，增加签名模式查询。仅显式要求才生成临时签名检查包。
- `Scripts/build-app.sh`、`Scripts/verify-app.sh`：本机开发证书与Apple身份区分签名选项，验证DR证书锚定且不使用cdhash；不增加关闭系统安全保护的entitlement。
- `Scripts/check-production-signing.sh`：现有生产要求不降低，新增AgentInference同团队、Developer ID、Hardened Runtime、时间戳及精确标识检查，补齐新增运行时的配套。
- `Tests/CleanerCoreTests/PermissionStatusTests.swift`：加入真实调用点对应的可读/拒绝/缺失/EIO检查；`Sources/CoreContractChecks/PermissionContract.swift`仅将Denied夹具改为明确Cocoa访问拒绝，保留断言。`Tests/permission-signing`准备跨内容DR验证及ad-hoc替换拒绝检查；执行需本批明确授权，尚不记为通过。
- `README.md`、`docs/architecture.md`、`docs/development.md`及计划：同步UI、权限状态、扫描降级、固定证书、手动分发与正式发行边界；未将旧审计记录伪装为当前状态。`Version.json`本批仅递增一次到0.2.37（70）。AGENTS.md继续保持删除。

通过系统Certificate Assistant创建SuperCleaner Local Development自签代码签名证书，RSA2048/SHA256，固定SHA-1为106EFE6967C308B187E41A6FD8E5DFA3B3C4480C。私钥由系统创建并仅存登录钥匙串；公开证书与指纹配置存于用户应用支持目录，不随Git/App/DMG分发私钥。系统信任与私钥使用授权交由用户本人确认，未改TCC数据库、Gatekeeper或系统保护。首次身份迁移仍需用户为新身份授权，后续同证书/Bundle ID的稳定性须经两个不同内容产物验证。

自审：去除重复入口100分、按错误性质识别权限100分、可访问扫描降级98分、证书固定和防静默退回100分、新worker生产门禁96分，均属本批明确范围或必要配套。主程序及全产品release编译通过，shell语法和git diff --check通过，仅有既存ApplicationUpdateModel弱引用捕获警告。当前等待用户确认代码签名信任及定向检查；尚未签名/替换最终App或宣称当前权限已恢复，没有提交或推送。

用户随后明确允许权限识别与签名稳定性定向检查，并表示已选择代码签名信任。PermissionStatusTests已运行5项、全部通过。实际核对发现证书窗口仍打开且信任尚未保存；在当前用户确认后关闭窗口触发保存，钥匙串验证交互阻塞，UI工具两次超时，security仍报告CSSMERR_TP_NOT_TRUSTED，已交还用户处理本人系统验证。未输入或索取系统密码，未通过命令修改信任、TCC或系统保护。签名稳定性验证和最终包交付仍待该步骤，不能当作已完成。

继续核对：用户完成系统信任保存与首次私钥使用确认后，固定身份有效。签名定向检查首次因仅接受anchor写法失败；实际自签DR使用certificate leaf固定指纹，依据Apple TN2206修正验证表达式后通过：不同代码DR一致、旧DR接受新版、ad-hoc同标识替换被拒绝。最小验证修正100分，未自定义宽松DR或改动生产门禁。重新拷贝最终编译的主程序/Helper/CLI及Core资源后同证书签名，深层验证通过，生成0.2.37（70）DMG并覆盖既有安装副本。三份123项一致，模型及许可通过；DMG SHA-256为0f8c9fd0903446edf9fff8da9a6a17db2def74361f7b5eaf9801628106fb9e9a。设置及扫描前窗口实机确认无文件夹授权区，FDA尚未验证但完成配置按钮可用；首次新身份FDA确认已交还用户，未执行真实清理或擅自改系统授权。

最终实机回归：用户授予固定身份FDA并重启后仍显示unverified。核实用户专用TCC目录不存在，系统同类目录存在，证实只覆盖单一路径的检查遗漏。新增testMissingUserProbeUsesReadableSystemProbe先失败（unverified而非granted、未访问系统探测路径），随后PermissionStatusService依次列举用户及系统专用保护目录，任一个成功即可验证；全部失败仍区分明确拒绝与未验证，不读取数据库。该必要局部修正100分，已经执行；没有继续扩张扫描/清理策略的全局修改。权限6项通过，重新编译并同证书签名，旧实际安装App的DR接受修正版。退出旧进程后覆盖安装，最终全扫描前预检实机显示Full Disk Access Available，无再次授权；未开始正式扫描或执行清理。最后界面核对后用户切换了窗口，未再争抢操作。

最终交付仍为本批一次版本0.2.37（70）；App、安装副本及DMG共123项文件/链接一致，最终DMG SHA-256为08b8078c425a98fa0e9064ced54beebc436adc26393f63336f104cf79c120ea0（取代本批中间包哈希）。签名、模型、许可、双语1012条、shell语法及git diff --check通过。详见[最终证据](../Tests/permission-signing/package-verification.txt)。临时镜像已卸载，临时夹具清理；本批无依赖变更、AGENTS.md保持删除、未提交或推送。下一步应使用当前包进行日常扫描；本轮目标内没有剩余必要修改，不启动额外优化。

## App管理说明与图标首帧（0.2.38 / 71）

用户明确要求修正App管理未验证展示，并检查首次进入卸载页图标加载过程。计划见[本批计划](permission-icon-presentation-plan.md)。

- `Sources/CleanerApp/PermissionsView.swift`：App管理固定显示“执行卸载时由系统确认”，不再把历史观察状态显示为当前系统开关；保留系统设置入口。PermissionRow状态文本允许nil并不生成空徽标，FDA状态不变。未改实际权限记录或卸载执行检查。
- `Sources/CleanerApp/ApplicationIconView.swift`：原State初始nil，页面出现后task才同步调用图标缓存，导致首帧占位、后续逐行替换。现在首帧直接使用现有缓存返回的原生NSImage，删除State、占位分支和task；32pt尺寸、缓存键、内嵌Helper图标回退及原有独立图标全部保留。首次未命中仍需系统解析本地图标；未宣称完全零耗时或加入额外后台预加载服务。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：仅新增本批App管理说明；1013条双语检查通过。
- `README.md`、`docs/architecture.md`、`docs/development.md`及本批计划：同步图标首帧与权限说明的边界。没有新增依赖、未重建AGENTS.md；指定.trae/rules/project_rules.md仍不存在。
- `Version.json`：本批仅一次递增0.2.38（71），同证书签名生成App/DMG并覆盖唯一安装路径；未运行含全套测试的打包总脚本。复用未变的Helper、CLI、推理程序、Framework与模型，仅更新主程序、Core文案资源和App/Helper版本元数据。

局部建议评分：移除误导徽标100分、删除人为图标延迟100分，均已执行。全局方案：复用共享缓存98分，全部调用统一修正；没有范围内必须实施的其他全局修改。已经逐处查看本批前后差异，均为用户请求直接对应的必要修改，未扩展扫描范围、删除策略或模型。Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告。未运行本批未明确授权的自动测试套件；通过编译、源码路径及真实界面验证，不把此前权限/签名定向授权扩大到其他测试。

最终包三份123项文件/链接一致；模型长度、SHA及许可、深层签名及旧实际安装DR兼容验证通过；DMG SHA-256为6acff3771593ebe66a6271ae110cabe21c7219a3736e0389476a5cfab319db5f，证据见[包核对](../Tests/permission-icon-presentation/package-verification.txt)。最终实机设置页版本0.2.38（71）、App管理无验证状态；扫描前同样正确，FDA Available且无新授权提示。应用模块只读扫描完成后，首次进入最终卸载页，94个应用/22项可卸载；首个实际截图中可见Microsoft各应用、Otty和RepairApp均显示原生图标，没有占位图。结合源码删除nil State和task确认不再由出现后的异步赋值逐行替换。未做逐帧性能测量，不宣称系统解析图标完全零耗时；其余模块扫描可继续，不将应用页核对当作全扫描完成。未执行文件清理、未提交或推送。

## Agent条目分隔与完整应用可见性（0.2.39 / 72）

用户要求Agent条目用横线区分，并指出截图中ChatGPT、Chrome、飞书、飞连、TRAE CN、Amphetamine未在卸载页找到；随后明确仍默认“可卸载”。计划见[本批计划](agent-separators-app-visibility-plan.md)。

先在实际0.2.38的已有扫描结果中切到All逐个搜索，六个均存在且Running（库存94项，Uninstallable仅22项），证实是筛选隐藏。没有为此扩大扫描根或改写发现器。

- `Sources/CleanerApp/AgentEnvironmentView.swift`：Skill/MCP共两处加入与大文件完全相同的1pt、secondary 0.12底部横线；保留List分组、两栏、Top3、选中/悬停背景及复选框。
- `Sources/CleanerApp/ApplicationsView.swift`：主动选择非All范围搜索无结果时，复用既有空结果区域说明范围限制，并指引已有All控件；不新增按钮、改变匹配或工具条。
- `Sources/CleanerApp/AppModel.swift`：曾尝试All初值，用户纠正后已撤销该行；最终保留原有uninstallable，当前批次无该属性的修改。没有更改扫描或卸载资格。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：新增同一条范围说明；1014条双语检查通过。
- `README.md`、`docs/architecture.md`、`docs/development.md`及计划：记录默认可卸载、完整清单与可卸载清单的区别、排查顺序及分隔标准；README同时纠正旧Top5/累计汇总的过时界面描述，与既有Top3/不显示汇总的实现一致。无依赖变更，AGENTS.md继续删除；指定project_rules.md不存在。
- `Version.json`：本批仅一次递增0.2.39（72），默认范围纠正后沿用该版本；更新主App/Core文案及App/Helper版本元数据，复用其他未变运行时，固定证书签名App与DMG并覆盖唯一安装路径。

局部方案评分：行分隔100分、遵循最终默认可卸载100分、空结果范围说明95分；全局方案：复用现有库存与运行保护98分，均已执行。逐处查看本批差异，均为请求直接对应的必要修改；未扩大扫描器、清理规则或Top3算法。Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告；未运行未经本批授权的自动测试套件、未执行删除、未提交或推送。

实机：同批分隔线包只读扫描后显示980项Skill、45份MCP，两种列表实际截图均有清晰细横线，白色行/浅蓝悬停背景和双栏保持。应用All为94/94；Chrome在Uninstallable为0且显示范围说明，切换All为1并保持运行锁。六个截图应用均在修正前库存中找到。最后只改回默认Uninstallable、重新编译和签名；Agent视图代码未再次变化，未重复进行整轮耗时扫描。最终启动固定安装副本、设置页确认0.2.39（72），留在清理中心；不将本批界面核对当作全扫描/包含分析完成或性能基准。

最终包App/安装副本/DMG的123项文件与链接一致；旧实际安装DR接受新包、深层签名、模型长度/SHA及许可通过。最终DMG SHA-256：125d162817d2405c11f4f2eb5584123168fbab251cee647f805b0be6a8995130，见[包证据](../Tests/agent-separators-app-visibility/package-verification.txt)。同批中间包哈希不再作为交付证据。镜像卸载遇到忙碌后重试正常eject，没有强制卸载；临时材料清理。没有范围内必须继续的修改，不启动额外优化。

## 应用状态短标签（0.2.40 / 73）

用户明确要求去掉应用名称旁重复的绿色Running标记，并把System protected缩短为Protected。计划见[本批计划](application-status-labels-plan.md)。

- `Sources/CleanerApp/ApplicationsView.swift`：删除名称旁的绿色circle.fill/Running分支及仅包住名称的HStack；保留应用名、Bundle ID、图标、右侧运行状态和不可卸载保护。没有改变行高、工具条或筛选逻辑。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：沿用“系统保护”键，将短标签分别改为Protected、受保护；筛选项与应用状态徽标共用，避免分叉文案。1014条双语检查通过。
- `README.md`、`docs/architecture.md`、`docs/development.md`及计划：同步状态显示边界；无新增依赖，AGENTS.md保持删除，指定project_rules.md不存在。
- `Version.json`：本批仅一次递增0.2.40（73）；更新主程序、Core文案和App/Helper版本元数据，复用其他未变运行时，同固定证书签名并覆盖既有安装App/DMG。默认uninstallable未修改。

逐处diff自审：删除重复标记100分、统一短标签100分，共用文案键的必要全局配套98分，均已执行；没有额外行为修改或剩余必要优化。Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告；未运行自动测试套件。实际预检FDA Available，原授权保留。只读界面核对扫描仅用于应用页面，已取消这次不需要的Agent模块，未修改包含索引或执行清理。最终画面核对通过：默认Uninstallable 22/94；Running 8/94的名称旁均无绿色标记，右侧橙色运行限制保留；Protected 65/94的筛选和行徽标均为短标签。已恢复可卸载，无选中/删除操作；Agent验证模块已取消，不当作全扫描完成。

包核对：App/安装副本/DMG共123项文件/链接一致，旧安装DR接受新包，深层签名、模型长度/SHA和许可通过；DMG SHA-256为a1d603d27460147ed5cd3363ce6bf8b769892c183111633481d2f0215bbc2fed。见[包证据](../Tests/application-status-labels/package-verification.txt)。未提交或推送。

本批最终界面核对后未再修改二进制或重打包；镜像已卸载、临时材料清理，固定安装副本保留本轮应用扫描结果。没有范围内剩余必要修改，不启动其他优化。

## Top3逐项完整路径tooltip与0.3.0版本

用户要求右侧Top3鼠标悬浮显示对应项的完整路径；随后明确要求将版本升为0.3.0。计划见[本批计划](agent-path-tooltips-plan.md)。

- `Sources/CleanerApp/AgentContainmentLabel.swift`：为每个target仅计算一次路径，Text仍按原规则中间截断；完整路径help从单独Text移动到target的整个名称/比例/路径区域，contentShape覆盖该项矩形。移除整栏累计分析help，避免用一段通用说明覆盖具体路径。Skill和MCP共用，宽度、Top3排序、覆盖计算及预选完全未改。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：删除两语言中不再使用的整栏提示键；路径为原始动态字符串，无需翻译，不加入截断或省略。1013条双语检查通过。
- `Version.json`：按用户显式minor版本要求，将0.2.40/73改为0.3.0/74，本批仅递增一次，不执行常规patch bump。
- `README.md`、`docs/architecture.md`、`docs/development.md`及计划：同步逐项悬浮范围、完整路径与原生help的约定；未新增依赖，AGENTS.md保持删除，指定project_rules.md不存在。

逐处diff自审：逐项绑定100分、移除父级冲突100分、两类共享配套98分，均是请求直接对应的必要修改，无剩余范围内必要优化。Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告。低影响原生tooltip按源码挂载层级、完整字符串和编译核对；未运行自动测试套件、未重复全扫描，也没有将未实测的真实鼠标停留弹窗写成通过。

固定证书重新签名，复用其余未变运行时，仅更新主程序/Core文案与App/Helper版本元数据；已覆盖/Applications/SuperCleaner.app，无额外安装副本。App/安装副本/DMG共123项一致，旧实际安装DR接受新包，深层签名/模型长度/SHA/许可通过。DMG SHA-256：13f4c1c8d2c4361cabad0f19b9320b07867352836ca8186dd9ae5c014a16fc73，见[包核对](../Tests/agent-path-tooltips/package-verification.txt)。不执行清理、提交或推送。

最终启动确认：设置页显示0.3.0（74），已返回清理中心。此后没有修改二进制或重打包；DMG已卸载，临时源码副本/marker清理，未再发起扫描。

## Agent行边界与首次权限提醒（0.3.1 / 75）

用户报告高亮/底线错位，要求权限交互按首次使用提醒、不要每次出现大配置窗口。最新明确请求优先于此前“每次全扫描集中配置”的交互要求。计划见[本批计划](agent-row-permission-onboarding-plan.md)。

- `Sources/CleanerApp/AgentEnvironmentView.swift`：两类行在同一padding后的内容容器上定义contentShape、高亮background及底线；ListRowBackground改透明，消除系统行内边距带来的宽/高差。仍用原选中或悬停条件、原颜色及Top3。
- `Sources/CleanerApp/AppModel.swift`：删除每次扫描必须打开sheet及preflightComplete/busy等状态；扫描入口直接beginFullScan并保留既有忙碌/执行保护。首次bootstrap判断FDA，已有访问不提醒，否则原生短提醒一次；正常保存introductionShown且返回后再次核对，避免多窗口重复。每次runScan刷新真实状态，scanAccessRequested只限制首次必要预访问次数；两个标记绝不代表授权。设置激活/进入时刷新，未改PermissionStatusService判定或清理执行。
- `Sources/CleanerApp/ContentView.swift`：移除大权限sheet，改为首次原生短alert，提供系统设置与继续使用。原删除操作sheet未变。
- `Sources/CleanerApp/PermissionsView.swift`：删除PermissionSetupView及重复集中配置入口；保留FDA/App管理/Helper原有系统入口，Form出现时刷新真实权限。Helper仍需明确操作和系统确认。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：删除8条失效modal文案，增加3条首次提醒文案，1008条双语检查通过。
- `README.md`、`docs/architecture.md`、`docs/development.md`与计划：替换旧逐次配置约定，说明记录仅控制提醒/请求次数、系统仍独立授权；补充统一行边界。README同时修正另一处旧Top5/combined描述，与现有Top3界面一致。无新增依赖，AGENTS.md保持删除，指定project_rules.md不存在。
- `Version.json`：本批仅一次patch递增0.3.1（75）。主程序/Core文案及App/Helper元数据更新，其余未变运行时复用，同固定证书签名并覆盖唯一安装App与DMG。

必要性评分：同容器绘制100分、删除大配置sheet100分、首次提醒持久化100分、设置状态刷新和真实执行保护配套99分，全部执行。逐处核对本批前后diff，均为用户请求或必要配套，未增加新的授权来源、依赖或清理能力。

Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告，未运行未经本批授权的自动测试套件。本机已有FDA场景实测：第一次启动无配置窗口；正常退出后introductionShown=1；第二次启动仍无窗口；全扫描直接启动四模块；设置显示FDA Available及既有App管理/Helper入口，无集中配置按钮。scanAccessRequested由App本次正常扫描记录为1。未修改TCC或为测试撤销授权；首次无FDA账户的短提醒分支按源码条件核对，未宣称该分支已真实弹窗测试。当前等待Agent库存检查行边界，未执行清理、提交或推送。

三份包123项文件/链接一致，旧安装DR接受新包，签名/模型长度/SHA/许可通过；DMG SHA-256：335527047aa8e48d8b0d4cb8ed0d47df3ec0af7d28622a5f1ae12701d345766c。见[包证据](../Tests/agent-row-permission-onboarding/package-verification.txt)。镜像已正常卸载。

本批最终实机核对：Agent扫描库存就绪后显示980项Skill及45份MCP；Skill普通文本悬停行与MCP已选行均确认高亮底边和横线重合，左右范围一致，未操作复选框或清理。库存生成时界面工具一次超时，重新连接后正常，未改扫描预算/范围，不把耗时当作性能验证。README及架构/开发文档另同步计时起点：直接beginFullScan后计入必要预访问，移除旧“权限配置后计时”的陈述。

全部本批计划已完成；临时源码副本、进程采样和镜像marker已清理，只保留公开签名要求及验证记录。最终二进制/DMG未再更改，未提交或推送。没有范围内剩余必要修改，不启动额外优化。

## Agent双栏对齐与MCP数量精简（0.3.2 / 76）

用户询问权限为何只有FDA显示Available，并要求去掉价值不大的每行MCP服务器数、Skill/MCP左右列靠左且右栏对齐。计划见[本批计划](agent-column-alignment-plan.md)。

- `Sources/CleanerApp/AgentEnvironmentView.swift`：删除每行MCP的server计数徽标和仅用于将其推右的Spacer；顶部配置数/服务器定义总数仍保留。两种左栏统一minWidth=0、maxWidth=infinity，允许按窗口实际剩余宽度收缩，不由长名称/路径最小宽度挤动覆盖栏。高亮、分隔线、选择逻辑未改。
- `Sources/CleanerApp/AgentContainmentLabel.swift`：有分析结果与状态文本由Group共用原360pt宽度、leading对齐、caption颜色；新增leading多行文本对齐及layoutPriority=1。各target的名称/路径、50pt数值列、Top3排序、完整路径help和百分比计算均保留，仅统一布局规则，不新增布局服务。
- `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`：删除仅用于被移除行徽标的“{0} 个服务器”键；顶部“服务器定义”统计键保留。1007条双语检查通过。
- 权限问题按当前代码解释：FDA有只读探测，因此可显示Available；App管理行有明确的“执行卸载时由系统确认”说明，state为nil，没有显示Available不代表未授权。本批不改PermissionStatusService、权限页或真实卸载检查，不读取/修改TCC，不为统一颜色而伪造授权。
- `README.md`、`docs/architecture.md`、`docs/development.md`与计划：同步双栏约束、移除行数量和权限展示边界；没有新增依赖，AGENTS.md保持用户要求的删除，指定project_rules.md不存在。
- `Version.json`：本批一次patch递增0.3.2（76），主程序/Core文案与App/Helper元数据更新，其余未变运行时复用；固定证书签名并覆盖唯一安装副本及DMG。

方案自审：共用组件优先于复制两份布局，复用原360pt而非引入新配置；左栏必须同时允许收缩，否则只设右栏对齐无法约束长内容。删除重复徽标100分、右栏共同规则100分、两类左栏配套98分、失效文案/文档同步98分，均为请求或必要配套。无范围内其他必要改动，不扩大扫描或覆盖算法。已逐处查看两个View的本批前后diff，无额外功能改动。

Release编译通过，仅有既存ApplicationUpdateModel弱引用捕获警告；双语检查与git diff --check通过，未运行自动测试套件。App/安装副本/DMG共123项文件与链接一致，旧安装DR接受新包，深层签名及模型长度/SHA/许可通过；DMG SHA-256为1a6100b747b5fa984840b19650c8099999c30ed01a113305922b0f3f4dd3b840，见[包证据](../Tests/agent-column-alignment/package-verification.txt)。镜像已正常卸载。新版设置页实机确认0.3.2（76）、FDA Available，无重新授权或配置窗口；只读扫描已开始，等待Agent库存核对布局，不执行清理、提交或推送。

本批最终列表视觉核对受锁屏阻塞：CUA报告Mac已锁定且物理输入后自动解锁暂停，要求本人解锁。已请求用户解锁，不尝试自动解锁、改系统权限或宣称Skill/MCP最终画面通过。编译/包/签名及设置FDA核对结果仍有效。
