# SuperCleaner 架构与当前实现

## 目标与边界

SuperCleaner 是 Swift 6 / SwiftUI 的 macOS 清理应用。核心原则是只读发现、明确选择、不可变计划、真实执行前复验、可恢复隔离和可审计历史。主要 Swift 目标为 `CleanerCore`、`AgentOverlapAI`、`CleanerApp`、`CleanerHelper` 与 `CoreContractChecks`，另保留系统库绑定 `CleanerZIP` 和 XCTest，定义见 [`Package.swift`](../Package.swift)。独立用户 CLI 已退役，生产 App 不再嵌入 `supercleaner`，Core 库、Helper 和契约工具继续保留。

## 模块职责

- `Sources/CleanerCore/`：扫描、分类、计划、安全策略、执行、历史、隔离调度、规则存储和 Helper 协议。
- `Sources/AgentOverlapAI/`：Agent模型资源及macOS13兼容的本机进程客户端；AgentInference为独立的macOS14推理可执行包，避免提高主应用系统要求。
- `Sources/CleanerApp/`：SwiftUI 页面与 `AppModel` 编排；将扫描结果、选择、执行进度、历史和调度状态投射到界面。
- `Sources/CleanerHelper/`：受限 XPC Helper 入口；双向按消息校验签名身份，按连接 UID 派生本用户范围，复用 Core 内的授权和无链接文件操作。
- `Sources/CoreContractChecks/`：不依赖 XCTest 运行环境的核心契约验证。
- `Tests/CleanerCoreTests/`：在完整 Xcode 环境中运行的 XCTest。
- `Sources/CleanerCore/Resources/`：生产运行时与核心契约使用的随包规则和双语资源；来源责任记录在 [`docs/rule-sources.md`](rule-sources.md)。

CleanerApplicationDelegate处理Dock reopen事件：如果主窗口已最小化，则展开所有最小化窗口；如果窗口已关闭，则通过SwiftUI的openWindow显式重开主窗口。两种情况都停止AppKit默认处理；已有可见窗口时保留系统默认行为。

清理后的窗口关闭与应用退出提醒复用 TrashReminderController 和 CleanerCore/TrashReminderState：本次累计清理量大于 0 且未确认本轮容量、未关闭自动提醒时，共用 Empty Trash / Cancel 工厂及执行器。只有关闭提醒额外提供“不再提醒”；手动清空始终确认，Settings 可恢复自动提醒。主窗口通过独立 NSView 观察 willCloseNotification，保留 SwiftUI delegate；明确退出使用 terminateLater，待公共任务及空间读取完成后 reply(true)，Cancel 与失败均允许退出。willTerminate 后不再处理随后的窗口关闭提醒。成功清空才确认容量；抑制不表示清空成功。详细规则见 [关闭提醒架构](../doc/architecture.md)。

清理中心、关闭窗口和退出的“清空废纸篓”共用显式确认入口，由上述同一控制器异步请求 Finder；不直接扫描或删除 Trash 路径。成功且核对已空后只记录启动时的会话累计字节，保留 suppress 偏好；取消/失败/超时不记录，新清理仍可提醒。结束刷新并等待卷容量读取完成；清空期间使用应用模型硬门禁阻止重复、并发清理和退出。正式签名的主 App 只增加 Apple Events Automation entitlement 与用途描述，保留原有发布安全检查。

## 扫描与计划

应用图标：ApplicationIconView首帧直接使用ApplicationIconCache的同步结果，不先显示空State占位再由task替换；缓存继续避免列表重绘重复读取。卸载页与系统清理页共用ApplicationIconCache，优先保留NSWorkspace返回的图标（含asset catalog与自定义图标）；仅与系统通用应用图标相同的内嵌应用沿真实Contents父子路径、按CFBundlePackageType=APPL识别最近的外层应用包，外层也缺图时继续向外。安装临时目录即使没有.app后缀也通过包元数据识别，并从CFBundleIconName/CFBundleIconFile声明资源读取图标。回退仅影响显示，不修改扫描记录、应用归属或卸载计划。通用图标比较限定为 32×32 RGBA 位图，不生成所有尺寸的 TIFF；继承仍返回完整原图。首次布局采样与回归

清理中心只负责六个维度的导航与行尾状态：移除行尾箭头和Cancel/Resume，模块内部DimensionActionBar保留取消/继续。首页completed/limited共用绿色勾选“扫描完成”，不改写模块原始状态、覆盖记录或清理资格。六行悬停复用应用卸载的accentColor/0.08背景，状态最右对齐。头部能力卡使用HStack的固有高度约束及子项可扩展高度，以最高内容自适应等高、顶部对齐。

首页采用无外层 ScrollView 的单页 VStack。顶部依次为扫描按钮/按钮下计时、紧凑卷容量、累计清理/清空废纸篓三个同行等高区域；六个范围行填充可用高度，头部安全卡保持紧凑。标题与行内留白缩小，说明单行并提供 tooltip，不扩大 detail 最小 760×560 pt 来规避裁切。

顶部三个区域为无容器底色、无边框的平面布局；间距与等高约束继续复用，原生按钮和头部安全卡样式独立保留。

标题下直接展示三张安全卡，位于扫描按钮行上方；原副说明和扫描范围小字已移除。扫描按钮加大并与标题文字左对齐，清空废纸篓按钮加大并靠右。六模块行显示非零的默认清理数量与容量；手动维度不显示零值。全部默认清理汇总系统推荐、大文件预选、Agent 自动预选及项目可清理预选，排除已取消勾选、未就绪、保护和失败项；模块统计与底栏使用同一合并后的可执行集合。

点击全扫描直接beginFullScan，不弹大权限配置窗口。首次启动在bootstrap期间读取FDA状态，已有访问则不提醒，否则仅一次原生alert；permissions.introductionShown记录已提醒并跨重启保留，不作为授权。首次扫描以permissions.scanAccessRequested记录只读预访问已尝试；FDA可用时跳过，否则使用现有预访问，在六模块启动前完成。之后不重复该配置流程，系统仍执行实际检查。

Agent分析可用性：列表上方直接呈现agentOverlapStatus；没有逐项结果时，AgentContainmentLabel显示真实状态而非仅“尚未分析”。策略不兼容时，AppModel清除失效排名和此前自动勾选，不影响用户手动选择，提示沿用设置中的全部重算入口；仍不静默复用旧口径或在普通扫描时自动重算。排名及预选继续使用同一分析器。

App扫描以ScanAccessTrackingFileSystem观察现有读取操作：记录EACCES/EPERM、Cocoa读取权限拒绝和存在但不可读的路径，原样重新抛出错误，由扫描器保留其既有跳过及保护行为。ScanAccessPresentation只调整GUI汇总和应用行提示，不删除原始coverage、limitations、所有权证据或放开清理资格。每个模块运行独立持有访问记录，旧回调仍受运行令牌限制；应用刷新和运行观察安装结果复用同一展示规则。

ScanContext.enforcesEntryBudgets在App扫描及应用刷新时为false，按统一策略停止执行系统、应用、大文件和Agent中对应的固定条目/资产计数上限，包括应用关联、规则发现、安装包发现和历史残留测量。默认仍为true，显式受限Core调用保留相应上限；本地模型和项目产物保留各自内容检查预算，执行复验仍必须完整通过。时间/字节等其他约束不随条目策略关闭。

ContentView仅为首次权限说明挂载原生alert；PermissionSetupView、大sheet及其集中配置入口已删除。设置页保留FDA/App管理与Helper，进入设置与从系统设置返回时刷新实际状态；扫描前也刷新，不以历史提醒标记伪造granted。多窗口同时启动时在读取结果返回后再次核对持久标记，避免重复提醒。

应用卸载行仅在分析状态不是complete时展示状态徽标；正常完成后只保留应用信息和可卸载项目/大小，底层分析状态与清理资格不变。

应用卸载页与大文件页采用相同的标题间距（5 pt）、标题内边距（24 pt）和筛选栏内边距（水平18 pt、垂直10 pt）。应用筛选栏使用caption字号并固定内容固有高度，防止分段筛选控件分配到多余垂直空间；扫描与卸载逻辑不变。

清理中心的介绍、六行范围及三项安全能力始终挂载；右侧仅为状态预留宽度，扫描渐进发布不替换首页结构。范围行始终可导航，取消/继续操作位于模块目的页。ContentView和CleanerGUI使用系统统一工具栏来对齐侧栏与标题栏边界。目的页底栏仅取消/继续当前模块，Recovery文件恢复和发布流程不变。

全扫描计时由AppModel持有本轮起止时间：beginFullScan直接设置起点，计入必要的首次预访问，六模块和Agent分析均空闲时记录终点。Dashboard仅用局部TimelineView按秒更新按钮右侧的时分秒文字；结束后切换静态文字，不每秒刷新整个AppModel。取消/失败后冻结，继续同轮扫描沿用原起点；完整重扫重置，完成后的单模块刷新保留上一轮全扫描用时。

`SystemScanCoordinator` 并行运行系统清理、应用、重复大文件、Agent 环境、本地 AI 模型和项目产物六个模块，并以同一 `generationID` 汇总为 `SystemScanReport`。模块结果可渐进展示；完整重扫会产生新 generation，使旧选择与旧计划失效。六个模块由AppModel分别持有任务和运行令牌，共享同一generation；SystemScanCoordinator按指定模块执行扫描器。取消只失效并取消对应任务，继续扫描仅重跑该模块并复用其他模块结果；用户更改大文件阈值时会重扫大文件模块。Agent 环境模块同时产出 `agentAssets`、`agentSkills` 和 `agentMCPConfigurations`：分别承载环境目录与真实清理单元、Skill 元数据与分组索引、MCP 配置来源和去敏服务器摘要。本地模型与项目分别以 `localAIModelInventory` 和 `projectScanReport` 保留清单、覆盖与保护证据；模块替换不清空其他维度结果。

Agent推理由独立的macOS14/arm64进程承载（AgentInference单独SwiftPM包，固定GemmaEmbed0.4.1），主应用与Helper继续以macOS13编译，根包仅保留原有Sparkle外部依赖，本批未新增依赖。AgentOverlapAI通过本机标准输入/输出顺序请求向量，取消请求会结束该Agent进程；该进程不承担本地模型库存扫描，六模块独立控制与标题栏对齐继续保留。

Agent 能力包含功能建立在GitHub基线 `75c9c26` 的清单和清理候选上。Skill目录与MCP配置文件分别作为同等分析/选择单元；MCP合并安全可见的服务器名称与已有本机用途说明，不连接服务、不读取敏感字段。EmbeddingGemma 2 Q8随App/DMG分发并校验固定长度、SHA-256与Apache 2.0来源。分析仅使用扫描快照，不二次打开manifest。

[`AgentCatalogPathPolicy`](../Sources/CleanerCore/AgentCatalogPathPolicy.swift)通过不跟随链接的文件身份逐级验证路径；Agent遍历跳过软链接，清单入口再次排除Skill目录、manifest、MCP文件及父目录链接（包括断链）。可独立发现的真实目标仍进入清单，链接和目标均不被修改。当前报告变化即按当前清单刷新分析参与集合，旧缓存中的链接不进入显示或预选。

[`AgentCapabilityExtraction`](../Sources/CleanerCore/AgentCapabilityExtraction.swift)提取能力描述；[`AgentOverlapAnalyzer`](../Sources/CleanerCore/AgentOverlapAnalyzer.swift)使用同一向量片段门槛计算每对同类对象的两个方向，缓存各自被覆盖的片段位图。多个目标取位图并集，重复片段只计一次；联合包含率达到用户阈值（默认85%）即可预选，沿用现有安全资格，不附加文本一致、平台或作用域门槛。统一预选规划优先处理需要联合覆盖的复合对象，保留提供覆盖的对象，防止整组互相预选。用户明确保留与页面筛选分离。

`AgentOverlapStore`以actor隔离原子读写 `~/Library/Application Support/SuperCleaner/agent-containment-index.plist`。每个对象的向量只存一次，每对缓存两个方向（包括零覆盖）的紧凑位图。普通扫描按稳定身份直接复用旧对象，不检测正文变化；仅当前清单内同类对象补齐缺失的双向关系，包括暂时不可访问后恢复的真实对象；已缓存向量不重新嵌入。未在当前清单中的旧数据可保留，但不参与新关系计算、排名或预选，无需为排除软链接重建整个索引。设置中的“重新计算全部包含关系”刷新Agent扫描快照并重建当前索引。用户阈值只改变预选，不重新推理；模型或策略版本不一致时提示显式重算。旧版本只导入本机说明，旧判据分数不复用。

Agent页保留GitHub基线布局、路径、复选框、原有筛选和分组；Skill与MCP行均绘制与大文件相同的1pt底部分隔线；右侧按单项覆盖率降序展示最多3个其他同类对象及路径，排除自身。对象信息与Top 3为顶部对齐的独立两栏；每个Top3条目的名称/比例/路径区域使用本条完整路径作为原生悬浮提示，不在整栏附加分析说明tooltip，不展示累计覆盖汇总行；内部预选仍用全部来源的覆盖位图并集计算，不截断为前3个。移除64片段采样上限，扫描快照保留Markdown标题用于排除参考目录；长描述拆分保留，表格描述参与提取。片段语义匹配参数收紧后策略版本变更，旧分数须显式重算，校验通过前不装入应用内存索引。Skill与MCP共用同一预选函数；类型切换只挂载当前页面，列表继续虚拟化。

应用关联仅接受完整 Bundle ID、带明确 `.` 边界的 Bundle ID/group ID，或与应用显示名完全相等的名称。只有 Bundle ID 或 group ID 的完整边界匹配可把非活跃缓存判为 `safe`；仅显示名命中的缓存保持 `review`。裸产品名或 token 前缀不构成所有权证据，避免相似产品名称误关联。Dashboard保留六项范围说明，并在右侧展示各模块状态；独立控制与扫描限制详情位于模块页，首页完成徽标不改写 `limited` 原始状态。

`ApplicationOwnershipGraphBuilder` 对已发现的应用建立统一所有权图，不再按单个应用独立猜测可删资源。相同 Bundle ID 的不同名称副本拥有同一批关联资源；签名声明的应用组按所有声明者合并。用户日志、WebKit/HTTP 存储、启动代理及 `/Library` 系统关联类别纳入图；系统文件、共享容器、仍有服务/配置引用的资源保持保护；经完整 Bundle ID 匹配并确认独占的用户数据可由用户单独勾选，默认不选。服务只受限解析 plist 中的显式路径，不执行脚本、不凭 Label 认定可删。应用清单不完整或图预算耗尽会保留覆盖范围提示，但不会覆盖已识别资源自己的归属和风险结论；引用不可验证的具体资源仍保持保护。

应用发现包括标准应用目录、Steam 已知库以及本地挂载卷的根级应用和 Applications 目录；不遍历整盘、备份或网络卷。挂载卷应用仅作为其他副本的所有权证据，不提供删除。生产发现/图构建有明确条目、深度和时间预算；限制通过覆盖信息公开。

`LocalApplicationInstallationInspector` 只读解析当前 Homebrew Cask JSON、Steam ACF/VDF、Mac App Store 收据线索以及安装收据+BOM 中的精确载荷路径，不根据包名猜应用、不删除收据、不运行安装管理命令。未识别的旧格式保持来源未知，不能声称来源已穷尽。Homebrew/Steam 或服务管理应用不进入本应用的直接卸载；提供原渠道说明与安全格式的命令复制。只对同签名团队的 app-bundle 卸载器提供显式确认启动，启动前完整复验签名；未知脚本不自动执行，官方工具的修改不属于本应用的恢复保证。

`ApplicationReferenceLocation` 的模型仅包含文件、行号与引用种类；配置/服务的命中文本、参数、令牌和环境变量不会进入证据、UI 或序列化模型。应用页展示图与来源信息。`ApplicationExecutionValidator` 在逐项执行前重新发现应用、重建图和管理来源；新副本、新服务或活动状态会拒绝旧计划。应用本体先移动后，原 Bundle ID 只用作关联项的归属锚点，不会把应用缺失视为删除其他副本资源的许可。

管理来源复验同时约束本体与关联项：新发现 Homebrew、其他安装管理器或服务管理时，旧计划中的缓存等关联项也拒绝移动。即使本体已经不在原路径，归属锚点仍必须通过管理来源检查；所有者证据缺失不能当作允许直接卸载。

系统清理的通用扫描在规则结果合并后执行一次有边界的历史卸载残留扫描，并把结果追加到同一份 `general` 候选集合，因此不增加新的 UI 模块。扫描只检查用户 `Library` 下的缓存、应用支持、偏好、保存状态和容器目录；只有名称为完整反向域名 Bundle ID、当前应用清单中不存在、未活动且不是符号链接的条目才进入候选。完整清单覆盖时，`Library/Caches` 下的条目可进入建议清理；其他目录只有在确认目录为空时才进入建议清理。这里的“可重建”依据是缓存目录本身的系统语义或空目录事实，而不是文件年龄或对具体应用内部格式的推断。非空的应用支持、偏好和容器数据进入建议保留。共享容器、Apple 条目、活动项、歧义项和清单不完整的结果不会升级为可安全清理。

`ContentView` 是维度操作区的唯一布局所有者。六个扫描维度在各自结果可用时统一挂载一个 `DimensionActionBar`，该组件复用 `SelectionActionBar` 的视觉布局，并根据当前维度绑定候选清理选择或应用卸载选择。各维度页面只负责内容和选择交互，不再内嵌独立底栏；`AppNavigationPolicy.showsDimensionActionBar(for:)` 是该外层承载关系的契约入口。当前维度处于等待或扫描状态时，底栏统一展示扫描进度和取消入口并禁用删除；扫描状态优先于执行状态展示。应用卸载与普通候选在执行态统一展示执行进度和停止后续项目入口，并禁用确认删除；应用批量卸载同时由 `AppModel.canExecuteUninstallBatch` 与 `executeUninstallBatch` 拒绝扫描态执行。Dashboard 的失败项安全重试在扫描期间禁用，并明确提示扫描完成后再重试。

`AppModel` 根据 `DefaultCleanupPolicy` 和用户选择构建候选集合，再由 `PlanBuilder` 生成不可变 `CleanupPlan`。“清理全部默认项”将系统推荐、大文件预选、Agent 自动预选及项目可清理预选中仍被勾选的内容合成一个计划；只有结果已就绪的模块可加入，用户取消勾选、保护项和失败待重试项排除。模块行、底栏与计划统一采用去重和父子合并后的操作数量与容量，手动选择项不进入该队列。应用卸载保持手动选择；项目产物在模块完成后预选可清理项并进入首页全部默认队列；本地模型必须手动选择，手动选择也不进入该队列。大文件默认勾选已核验的重复项和符合安全条件的安装文件，可由首页全部默认清理统一执行，也可进入对应页面调整。Agent 扫描默认不选，能力累计覆盖达到设置阈值且安全可选的Skill/MCP会由Agent分析加入预选，可从首页统一执行仍保留勾选的自动项，手动项在模块页确认。Agent 环境页的 Skill 和 MCP 共用显示筛选，未手动选择显示筛选时，当前 Skill/MCP 类型和平台有已选项则显示「已选中」，否则显示「全部」；用户手动选择后保持其筛选。页面按平台、范围和资源类型查询、分组，并支持删除决策。`ScanDiscoverySummary`计算应用、大文件、Agent平台、Skill目录、MCP服务器定义、本地模型和项目产物数量，独立于用户当前选择；清理中心保留固定范围说明，具体清单进入对应模块查看；扫描受限、失败和取消仍保留其真实状态。确认界面不修改文件；确认后进入真实执行。`CleanupExecutor` 不信任扫描时状态，会再次检查：

1. 计划是否过期；
2. 规则版本是否一致；
3. 路径是否仍满足 `PathPolicy`；
4. 项目是否正在使用；
5. 当前 `FileIdentity` 是否与计划一致。

任一检查失败时，对应计划或项目被拒绝/跳过，不以旧扫描结论继续写入。

历史残留在执行入口额外复验 Bundle ID 是否重新出现、路径是否仍在允许的用户 Library 根目录内、条目是否仍未活动，以及文件身份是否与计划一致；任一条件变化都会拒绝旧计划。

计划时效在异步安全复验、活动检查、身份读取和隔离目录准备后重新检查；Helper 未处理而回退用户态前再次检查。已过期计划不得启动新的文件移动或 Helper 请求；有效期内已发出的请求继续按在途请求与不确定结果机制收敛。

## Agent Skill、MCP 与环境目录

`AgentResourcePathRegistry` 集中保存供应商路径规则，`AgentWorkspaceScanner` 通过用户级、项目级、管理员级和 `CODEX_HOME` 根目录发现资源。项目发现采用有深度和目录数量上限的只读遍历，跳过版本库元数据、依赖与构建目录。Skill 扫描只受限读取 `SKILL.md` 头部构建 `SkillCatalogEntry`；`MCPConfigurationCatalogSupport` 只从 TOML/JSON 中提取服务器名称、传输方式和项目归属，不把 command、args、env、headers、token 或 secret 放进数据模型。MCP 配置与 Skill 仍属于保护资产。

`AgentSkillCatalogPresentation` 把 Skill 与 `agentAssets` 中实际可删单元绑定，并通过 `AgentCatalogRegistry` 推断一级展示分组。用户选择“加入删除计划”时，真正进入 `selectedIDs` 的仍然是关联且当前允许删除的 cleanup units，不会绕过保护规则。MCP 分区按平台、范围和配置文件展示去敏摘要；目录分区继续展示实际路径、资源类型和目录级风险。

Agent 目录扫描的预算限制、身份读取失败和目录枚举失败均携带路径限制与平台覆盖证据。完整目录遍历不再因为旧深度参数截断；空目录不误报，读取失败不混作预算耗尽。`AgentAssetInventory.providerCoverage` 与完整扫描报告共同保留平台状态，单模块刷新继续传播；[ReviewRegressionContract](../Sources/CoreContractChecks/ReviewRegressionContract.swift) 直接检查深目录、读取/身份失败和只读行为，不依赖已退役的 CLI JSON 输出。

重复大文件模块先用 Spotlight 获取大文件候选。索引不可用时，回退到受深度和条目预算约束的目录扫描。发现阶段结束后，模块先跨格式核验精确副本，再把 ZIP 与同级文件夹进行完整对照，最后发布一份带建议的大文件报告。两层各自限制读盘和耗时。ZIP 用清单中未压缩文件的总大小判定匹配文件夹能否达到门槛，再核对磁盘上的路径、类型和大小。完整匹配的目录才进入内容比较，所有成员都分块核验。

重复建议使用原候选 ID 和 `LargeFileCleanupProof`，记录待移走对象及保留路径。安装包预选复用 `InstallerDiscovery` 的安装文件格式表及大文件本地快照检查，不另扫目录或读取安装包内容。已核验的副本组和 ZIP 保留件优先，避免安装包规则把保留对象加回选择。已完成的清理会按路径使受影响的证据失效。计划拒绝同时移走保留路径，执行器在实际移动前复验快照，含重复建议的批次进入手动保留的隔离区。页面默认展示「全部大文件」并按选择排序；切换到「重复大文件」后，底栏只提交该范围内的选择。见 [重复大文件实施与验收](../doc/large-file-duplicates-plan.md)。

桌面端在启动大文件模块时读取 `largeFiles.preselectInstallers` 的当前设置值并传给协调器。全量扫描、刷新和继续扫描共用该入口。扫描结果保留安装包类型证据；只有安装包规则的默认选择标记受设置影响。当前结果和手动勾选不会被修改，查重证据仍有优先级。

## 本地 AI 模型与项目产物

[LocalAIModelScanner](../Sources/CleanerCore/LocalAIModelScanner.swift) 是独立的 `localAIModels` 扫描器，输出 `LocalAIModelInventory`，不把模型识别混入 Agent 能力分析或系统默认清理。固定十个根覆盖七类 `LocalAIModelProvider`：

| 供应商 | Home 下的固定根 | 清理单元 |
| --- | --- | --- |
| Hugging Face | `.cache/huggingface/hub` | `models--` / `datasets--` 整仓库，保留 blobs 与 snapshots 的关系 |
| LM Studio | `.lmstudio/models`、`.cache/lm-studio/models` | publisher/model 目录 |
| Ollama | `.ollama/models` | 按 manifests 中 name:tag 逐模型选择，保留未选模型引用的共享文件 |
| PyTorch | `.cache/torch/hub/checkpoints` | 识别出的模型文件 |
| Whisper | `.cache/whisper` | `.pt` 模型文件 |
| Keras | `.keras/models`、`.keras/datasets` | 已识别模型或数据集条目，排除工具配置根 |
| GPT4All | `Library/Application Support/nomic.ai/GPT4All`、`.cache/gpt4all` | GGUF/GGML 及命名受限的模型 `.bin`，不整库删除应用支持数据 |

清单条目统一为 `review` 或 `blocked`，`defaultSelection` 为 false 且要求显式选择。模型不检测或展示运行状态；相关进程或活动探测失败不影响手动删除。保护路径、凭据、读取失败、布局不符和检查预算耗尽仍不能获得可执行资格。候选路径和祖先必须是可验证的非链接路径；仓库内部的链接随整体移动，但不遍历目标、不重复计量。`validateForExecution` 再检查供应商布局范围、根身份、文件身份、大小与元数据指纹，防止扫描后变化的旧候选执行；该指纹不等于对模型所有内容做逐字节哈希。

模型目录和普通文件均严格拒绝变化，安全验证是否执行与“是否允许内容变化”解耦。初始验证通过不代表获得后续移动许可；实际移动前仍终验保护、范围、身份与指纹，公共执行器在 Helper 未处理而回退用户态后的移动边界也保留终验。等待期间发生内容变化时拒绝移动，不因 `allowsExecutionContentChanges == false` 跳过最终验证。

[ResourceCleanupView](../Sources/CleanerApp/ResourceCleanupView.swift) 同时承载模型和项目页面：模型按供应商显示，Ollama 显示具体模型名称与 tag，并说明共享文件保留语义；项目按候选的 `project-root` 证据分组。布局参照应用卸载与重复大文件：独立搜索/范围/排序、全宽可折叠分组、可见项三态选择、路径与大小，Finder/永久保护操作统一放在原生右键菜单，不常驻巨大检查器。窄窗口过滤栏分两行；筛选不清除选择，也不改其它维度。勾选复用 AppModel 的单项与分组入口，剔除未完整核验项；项目与模型均不因运行或未知活动状态限制选择和删除，不因模块 limited 禁用全部已验证候选。保留外层 `DimensionActionBar` 和重新扫描，不建立另一套执行器。

项目产物由已有 [ProjectArtifactScanner](../Sources/CleanerCore/ProjectArtifacts.swift) 接入 `projects` 模块，仅当项目默认勾选设置开启时，可清理预选项同步纳入全部默认清理。项目指含 `package.json`、`Cargo.toml`、`Package.swift`、`pyproject.toml` 等 manifest 的源码工程；产物指其 `node_modules` 依赖、`target` / `.build` 编译输出及 `build` / `dist` 生成目录，不能凭任意同名文件夹判定。`ProjectScanRootsStore` 默认包含常见项目位置及 `AgentResourcePathRegistry` 集中维护的 worktree 容器；设置中的 `NSOpenPanel` 允许多选目录，保存到 `project-scan-roots.json`。设置保存已有报告时只重扫项目模块，没有报告时只保存配置；首次全扫描从清理中心沿原权限准备流程发起。

扫描按项目 manifest 聚合五类产物，使用只读 Git 索引判断 tracked 内容，不调用构建脚本或仓库 hook；非托管嵌套 `.git`、部署密钥、不可读内容或检查预算耗尽使候选 blocked。Git ignored 不代表可重建或可安全删除。项目产物页面在路径与内容检查通过且默认勾选设置开启后预选可清理项（包括 Git 跟踪项），初始关闭，仍需用户确认；近期产物也必须满足同样的可清理资格。

项目产物不检测或展示运行状态，活动或探测不可用不阻止选择和删除。单模块刷新及执行不请求项目/进程活动探测；完整扫描保留其它维度需要的共享探针。执行前重读扫描根、manifest、Git 跟踪状态、密钥与目录内容，之后复用既有 journal、隔离、历史、恢复和保留策略。依赖目录内的链接随目录移动，但不遍历、不统计也不删除链接目标。

## 卷容量与逻辑字节

[DiskCapacityReader](../Sources/CleanerCore/DiskCapacitySnapshot.swift) 对 Home 所在文件系统调用 `statfs`，以 block size × blocks 得到总量，以 block size × `f_bavail` 得到当前用户可用量，`DiskCapacitySnapshot.usedBytes` 为总量减可用量。该口径不叠加系统估计的 purgeable 容量，也不把家目录扫描树当作整卷空间分布。

[DiskCapacityMonitor](../Sources/CleanerApp/DiskCapacityMonitor.swift) 独立保存容量快照或明确读取错误，仅侧栏订阅。启动、每 60 秒、应用激活及扫描/清理/恢复/清空废纸篓后重新读取。读取在 utility 后台执行，单次并发、重复容量不发布，避免使清理列表重算；失败清除过期快照并显示错误，不用 0 掩盖。`CleanupSessionSummary` 累计成功回执的逻辑字节，候选合计同样不是物理释放测量。移到 Trash/隔离区、APFS 共享与系统并发写入都可能使该累计值与卷可用量变化不同，界面不以累计值承诺已释放容量。

## 执行日志 → 执行 → 历史 → 调度

真实执行由 `CleanupExecutionCoordinator` 串联，顺序是：

1. `ExecutionJournalStore.upsert` 先原子写入待执行日志；
2. `CleanupExecutor.execute` 将通过复验的项目移入 App 自有隔离目录，并验证源/目标状态；
3. `HistoryStore.upsert` 原子保存 `OperationReceipt`；
4. `QuarantineMaintenanceCoordinator.register` 按保留策略写入 `QuarantineScheduleStore`；
5. 仅在历史和调度均完成后删除执行日志。

协调器在写执行日志前同时检查待处理日志与历史，已出现过的 `planID` 会立即拒绝，避免同一计划再次关联到旧隔离目标。如果 App 在中途退出，启动时 `recoverPendingExecutions` 根据源路径与隔离路径的真实状态重建回执。若历史已写入但调度尚未完成，则复用已持久化回执补齐调度，避免重复执行文件移动。

## 历史、恢复与隔离调度

历史回执记录每项结果及总体状态。恢复和彻底删除在文件副作用前先写 `resolution-journal.json`，其中保存操作类型、源回执、源路径以及恢复目标；冲突恢复目标由 resolution ID 稳定生成。历史与调度完成更新后才移除日志。启动恢复会重放未完成 resolution，根据持久化目标和当前文件状态补写历史，避免文件已处理但记录永久停留在隔离状态。

恢复只接受属于对应计划和候选的隔离路径；原路径冲突时恢复到相邻新路径，不覆盖现有内容。彻底删除也只处理回执拥有的隔离内容。恢复、手动彻底删除、自动维护和重新调度按 receipt ID 使用同一生命周期互斥；文件处理完成后、提交历史前重新读取最新回执，避免并发操作以旧快照覆盖新状态。若 purge 日志证明源在删除准备时存在，而启动恢复时该源已缺失，则该持久化删除意图收敛为 `permanentlyDeleted`；若准备时源本就缺失则保持失败。任何未解析结果都保留 resolution journal，只有全部项目进入对应终态且历史、调度持久化后才清除。

`QuarantineScheduleStore` 保存保留策略、到期时间、最近尝试时间和自动删除失败原因。`AppModel.bootstrap()` 在启动后恢复未完成执行、迁移缺失调度并处理到期项，之后每 60 秒检查一次。失败项继续保留在隔离区，并记录：

- 稳定错误码 `itemDeletionFailed`；
- 首个具体错误消息；
- 失败项目数量；
- 最近尝试时间。

待执行日志的后台复验也参与同一 receipt 生命周期互斥，并在获得互斥后读取最新历史。复验提交不覆盖已有保留策略、到期时间或失败重试元数据；仅在缺少调度时补建，无隔离内容时移除调度，避免恢复后旧隔离状态或旧保留策略被重新写回。

自动删除在更新历史前先把本次尝试及 `historyPersistenceFailed` 结构化状态写入调度；即使历史提交失败，`lastAttemptAt` 仍然持久化。到期查询对已有失败采用 1 小时重试间隔，因此不会每分钟重复执行；App 关闭期间没有常驻服务，下次启动后继续补偿。

自动清理结果以 `standardizedFileURL.path` 作为跨模块身份键。某一路径成功后，`AppModel` 会同步清除六个模块中指向该路径的所有 UUID 选择，将所有别名加入当前扫描的默认队列排除集合，并移除同路径旧失败状态，防止同一文件被不同模块重复清理。

## 集成状态与生产验收边界

### Helper

Helper 使用 macOS 13+ `SMAppService.daemon` 注册 / 异步移除，plist 位于 `Contents/Library/LaunchDaemons`，`BundleProgram` 指向同一已签名应用中的可执行文件；不使用 SMJobBless 或直接写系统启动目录。设置页分别展示系统批准、连接验证和操作会话授权，不把注册成功当作可执行。升级后提供先移除再注册的入口，失败保持未启用；移除始终保留恢复内容且无许可门禁。

`HelperSigningIdentity` 从运行代码签名取得正式 Bundle ID 和 Team ID；ad-hoc、示例身份和调试可附加签名不作为根文件操作身份。客户端与 Listener 使用公开 `NSXPCConnection.setCodeSigningRequirement` 对每条对端消息约束精确标识符、Apple 证书链和同一团队，不做 PID-only 验证，也不调用私有 auditToken。Listener 从连接有效 UID 和系统账户数据库派生范围，客户端不能指定他人 Home。

用户需先显式验证协议 v3 连接并通过系统管理员授权。当前内存会话没有项目内固定五分钟倒计时；退出、主动撤销或系统授权校验失败后不能用于执行。每次请求仍绑定短期 token、操作摘要、planID、UID、文件身份和全进程去重 nonce。AuthorizationExternalForm 仅经 XPC 传递，不写入日志、历史或磁盘。Helper 独立检查系统授权，根进程不弹授权 UI、不代为取得新权限。

`HelperFileOperations` 只允许 `/Applications` 和 `/Library/Input Methods` 中应用本体的隔离，以及本用户恢复区中对应计划应用的恢复 / 清除；输入法目录并不整体开放删除。路径逐段以目录描述符和 O_NOFOLLOW 打开；拒绝跳转语法、链接祖先、符号链接应用、非本用户恢复容器、网络文件系统、挂载点、身份变化和目标冲突。移动使用不覆盖的 renameatx_np；清除以 fd 相对 unlinkat 删除链接本身，不跟随目标，且有条目、深度和时间限制。没有任意系统删除、脚本、服务终止、chmod/chown 或跨卷复制接口；系统服务仍交回原安装来源处理。

`CleanupExecutor` 通过 `PrivilegedApplicationOperations` 接入，在已授权会话中对应用本体调用 Helper；未授权只尝试既有用户态路径，权限错误不会触发自动提权或重试。移动、恢复均验证移动后的身份。取消已发出的修改请求会等待该项结论，只停止后续项目。连接中断 / 超时或无法判断的移动结果设置 `verificationNotBefore`，保留执行日志和确定的隔离目标，待所有可能的在途请求过期后只读复验；迟到完成回写原回执，不重复移动。启动以及空闲维护期间复验；运行中的计划不参与恢复重放。

以上已通过本地临时目录、协议与执行契约及打包门禁，但尚未在真实正式签名 / 公证版本上安装、授权或完成双向认证连接。实际生产行为仍是独立发布验收条件，不得用契约或 self-check 替代。

实现依据：[Apple SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice?language=objc)、公开 macOS 15.5 SDK 的 SMAppService/NSXPCConnection 头文件，以及 [Code Signing Requirement Language](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/RequirementLang/RequirementLang.html)。本机契约使用 Security 框架实际编译 requirement；`exists` 对布尔 false 的语义用于拒绝调试可附加签名。签名身份不是客户端提供的自由文本。

### RuleStore

`CleanupRuntime` 从 `RuleStore.currentPack()` 获取当前已验证规则，缺少已安装更新时加载随包 `bundled-3`。`CleanupRuleEngine` 按来源、系统版本、粒度、活动工具、目录完整性、保护例外、年龄及默认选择生成候选。每条规则独立扫描，一条规则失败不丢弃其他规则的已验证结果。更精确目录规则覆盖宽泛发现规则。未知缓存默认保留；uv 管理缓存禁止直接移动。

`AppInfrastructure` 是 GUI 的构造 seam：它隐藏文件系统、规则运行时、隔离执行器、历史/日志/调度存储及 Helper 授权适配器的装配。`HelperSettingsModel` 独立拥有 Helper 注册、XPC 身份验证、短时授权、撤销和升级前停用状态；`AppModel` 只保留跨功能产品状态与互斥策略。

规则执行身份由版本、规范化内容摘要与持久激活 ID 组成；摘要以结构化字段编码，保留字符串 / 数组边界。同版本换包、撤销、显式回滚均使旧计划失效，重复读取同一已安装包身份稳定。执行器在计划入口及每个项目前重读当前规则，重新验证活动与目录内容，不依赖 UI 快照。

`RuleStore` 以单个 `state.json` 原子切换当前和上一份签名包；首次提交前先持久化等价 baseline，避免写入失败留下仅 marker 的不可用状态。签名 high-water pack 防止旧源重放；历史撤销保存完整签名证据，后续包遗漏撤销或用户回滚都不能复活已撤销规则。发布者发送累计撤销时可压缩旧证明；包、证明数量和状态文件都有大小限制。原 current/previous 格式只读兼容，显式更新时迁移；已初始化状态缺失不降回旧格式或随包规则。当前包验签失败时仍可显式切回可信上一份；损坏的上一份不作为可用回滚目标。

`RuleUpdateService` 将网络下载、文件导入、验签、安全 schema、单调发布时间和原子提交接成同一流程。`HTTPSUpdateTransport` 使用 ephemeral URLSession 和流式文件输出，逐跳限制 HTTPS/443/明确主机、重定向数量、响应、字节和累计时限；无 Cookie、持久缓存或凭据，不覆盖现有输出，失败 / 取消移除其部分文件。TLS 校验交给系统，不接受自定义信任覆盖。网络行为以 URLProtocol 代送响应验证真实 delegate 路径；尚未连接用户实际发布源或验证其 TLS 部署。

应用更新由固定版本 Sparkle 2.10.0 承担下载、DMG Ed25519 校验、挂载、Apple 代码签名完整性、原生安装授权和原子替换/安装失败恢复；移除原来无人调用的 JSON `UpdateService` 骨架，不维护第二套安装器。`ApplicationUpdatePolicy` 同时供生产 delegate 与发布预检使用：只接受已验证签名 feed、严格递增整数 CFBundleVersion、明确 HTTPS 主机和完整应用 DMG，拒绝 ZIP、包安装器、增量和不合理声明长度。SDK 负责 OS/硬件适配。自动检查、下载、系统画像、远程 release notes 和 JavaScript 禁用；签名 feed 失败不设超时放行。

`ApplicationUpdateModel` 仅在正式身份/公开配置/Info.plist 一致时允许显式操作。与扫描、清理、恢复、规则激活互斥；先撤销会话并异步解除 Helper 注册，失败就不检查更新。`ImmediateUpdateDriver` 不提供延期安装；应用 delegate 在准备阶段拒绝普通退出，防止 Sparkle 的退出安装路径绕过最后确认。最后明确批准安装后才允许退出；失败/取消解锁，Helper 始终需在设置中手动重新启用，恢复记录不改写。

信任边界：运行时信任配置的 Ed25519 公钥，SDK 保留其证书轮换语义，并非额外实现了“每次安装必须与旧版同 Team ID”的验证。发行门禁独立要求主 App / Helper / AgentInference / Sparkle 嵌套代码均为配置 Team 的 Developer ID、Hardened Runtime 和安全时间戳，并验证公证/staple/Gatekeeper。SDK 的 Gatekeeper 预热不等于强制公证验证。应用下载使用 SDK 传输，不承诺规则下载模块的逐跳主机、累计时限或流式容量限制；归档声明长度限制及签名校验不能冒充网络资源限制。实际证书、线上源和干净机升级仍待验收。

`SignedApplicationRelease` 是离线发布门禁，不是运行时更新器：用公开配置验证官方 Sparkle 签名 XML 格式、单版本 metadata 与 DMG 签名/长度，生成 SHA256；拒绝 DTD、元数据歧义和链接归档。`publish-release.sh` 创建不覆盖的 staging，明确 `--publish` 才访问签名 Keychain、签名 DMG 并提交 Apple 公证；只输出本地产物，不发布到网络。`LOCAL-GATES-PASSED` 不替代干净机验收。

设置页显示更新来源、签名下载、离线导入、取消及确认回滚。更新操作与扫描、清理、恢复、Helper 修改、后台维护互斥；未决文件操作先复验。成功激活清空旧扫描、选择和项目确认，重复的当前包不清空状态。执行器仍独立重读磁盘，不把 UI 互斥当作安全依据。

`ReleaseConfiguration` 只接受正式身份、公开 Ed25519 公钥和无凭据的明确更新源；未知字段（含私钥字段）、源 URL query/userinfo 和无效主机均拒绝。生产 `CleanupRuntime` 使用该配置加载已安装签名包。`CoreContractChecks --check-packaged-rule-config` 将契约工具自身与实际打包 Core 资源复制进临时 Fixture.app，直接验证应用资源解析、公开配置、激活身份与签名规则发现，不再依赖用户 CLI；只读行为和保护拒绝由 Core 契约保留。配置仅在显式提供时嵌入 App 并受外层签名封装，默认不包含示例配置。实际发布源和干净机验收仍独立完成。

`ProtectionStore` 原子保存用户保护路径，`ProtectionPolicy` 检查字面路径、当前解析路径与加入保护时的解析路径；父/子目录重叠都会阻止整体删除。GUI 设置可添加和取消保护，候选列表可右键保护。扫描结果、计划及执行使用同一策略；执行每项前重读磁盘，读取失败或清单不是普通文件时拒绝删除。默认还保护凭证、钥匙串和 App 自有恢复数据。

安装包发现通过 `InstallerDiscovery` 遍历多个已知下载来源，跳过后代符号链接，显式根链接可解析。ZIP 只读取清单、验证安装结构和完整性，不解压内容到磁盘。目录安装包计量遵守同一预算，累计超时/条目耗尽/遍历失败会丢弃该次安装包结果。

### 发布状态

构建脚本默认使用本机固定指纹的证书；本机开发证书与Apple正式发行证书分别处理，不静默退回ad-hoc。主App、Helper、AgentInference及嵌套代码沿用同一选定身份，后续产物的DR由证书锚定。独立 CLI 的 build/copy/sign/required identifier 已移除，其余签名和发布门禁保留。首次由旧临时身份切换仍需用户授权当前版本，各Mac的授权独立；本机开发签名不包含Apple公证、staple或正式发布验收。发布门禁见[`docs/development.md`](development.md)。

Agent 默认规划：应用层以当前用户`.agents/`路径标记默认保留对象，以`.cache/`路径标记独立缓存预选，Skill/MCP共用分析器。规划先扣除用户保留与不可选对象，加入合格缓存，再排除这些待删来源计算其余对象的包含关系；优先用已保留来源达到阈值，保留覆盖提供者，避免整组删除。缓存预选在扫描结束立即执行，不等待模型；策略不兼容时清除旧包含建议后仍可预选缓存。

卸载筛选栏：ApplicationScopePicker桥接原生NSSegmentedControl，以fillEqually分配固定420 pt；搜索260 pt，排序/计数各140 pt，避免选择状态或计数变动引起重新分配。ViewThatFits按可用宽度选择单/双行布局。外层仍为caption和水平18/垂直10内边距，不显示Refresh Apps，不以整行固定高度裁切控件。

覆盖结果用Grid的统一百分比列右对齐，路径行跨两列；不同路径的Skill保持独立身份。右侧targets仅由本次activeIDs内的对象生成，因此对应对象仍在本轮清单；平台/已选筛选和分组可改变可见位置，不应误作未检索。注册目录的scope优先于项目重复遍历的scope，用户主目录资源不再误标Project。

FDA状态在首次提醒判断、每次扫描开始及设置页进入/激活时检查；其余启动不触发全目录预访问。依次列举用户/系统TCC保护目录，不读取数据库；任一成功为可用，拒绝/缺失/其他错误按原逻辑区分。已提醒与预访问记录仅控制交互次数，未验证/拒绝仍可扫描可访问范围。App管理仅显示固定说明，清理保护不变。

应用清单可见性：AppModel 初始范围为 Uninstallable。三个范围互斥且无遗漏：系统应用无论运行状态均归入 Protected；其余应用运行中进入 Running，未运行进入 Uninstallable，All 汇总全部。系统身份依据字面或实际 `/System/` 路径，后装输入法及 Apple 签名本身不代表系统保护。删除静态写权限推断管理员需求的字段与拦截；`ApplicationUninstallCoverageState.running` 单独表达等待退出，保留预备清单但不暴露执行项，退出后移动到 Uninstallable 并复用原项目身份；重新启动则移回 Running 并清除卸载选择。实际操作被拒绝时沿用权限恢复流程。第三方输入法本体路径在 `PathPolicy` 和 Helper 中一致开放；通用输入法缓存保护保持独立。详见 [本次方案](../doc/application-uninstall-eligibility-plan.md)。

应用状态显示：名称旁不再重复绘制绿色Running标签；右侧分析状态仍显示运行限制。原“系统保护”短文案统一为Protected/受保护，作用于同一筛选和应用行徽标，不改变systemProtected枚举、默认可卸载范围或执行保护。

Agent行绘制：系统List行背景透明，内容padding之后设置contentShape、选中/悬停background及底部横线，三者共用一块边界；不再将高亮挂到范围更大的listRowBackground。Skill/MCP同时遵循，选择规则不变。

Agent双栏：Skill/MCP左侧内容统一minWidth=0、maxWidth=infinity，覆盖组件统一360pt宽度、leading多行对齐和layoutPriority=1；已分析与状态分支共用外层约束，内容长度不改变右栏起点。MCP行删除server计数徽标和其Spacer，原servers数据及顶部汇总保留；不影响解析、覆盖或清理资格。

跨模块默认计划通过 DefaultCleanupSelection.buildPlan(using:) 将原始候选先交给 PlanBuilder；不得将已去重的展示候选直接当成计划输入，以免系统安装包别名或父目录遮蔽大文件保留副本证明。执行和回执使用最终 plan.selectedItems。

三张安全卡和下方操作行统一使用左 52pt、右 24pt 的外边距；左右边界分别对齐标题文字和废纸篓按钮右边缘，安全卡三列与操作行均用 12pt 间距，避免把边距分别加在首列与末列。

Scan 按钮可见高度为 56pt（约原来的两倍），使用专用 SwiftUI ButtonStyle 保留按压、禁用、焦点轮廓和原生 Button 无障碍语义，计时在按钮右侧，左右外边界保持一致。模型/项目页的顶部 NSButton 复选框显示本地化 Select All/全选，组内仍为无文字小复选框；顶部摘要至少 200pt，计数使用固有宽度，ViewThatFits 在窄窗口分行。Project Artifacts 的标题、侧栏和首页统一来自同一个翻译条目。

设置中的项目扫描目录与项目页共用 `ProjectScanRootsStore` 和 `project-scan-roots.json`，不复制存储。44pt 行、132pt 内部滚动视口只限制可见三行，完整目录列表仍保留；草稿添加/移除后统一保存或撤销。设置首次保存不触发扫描，已有报告只刷新项目模块。保存与新扫描、权限流程继续、取消模块续跑及清理互斥；取消刷新后范围不一致的旧项目结果不可执行。配置错误在设置和项目页均可见，包括无扫描报告时。

资源默认入口只在本模块成功发布新结果时应用：模型仅清除旧模块选择、不预选；项目清除旧 ID 后仅在设置 projects.preselectArtifacts 开启时预选可清理项（含 Git 跟踪项），初始关闭。项目仅保留 All / Protected / Selected，初始有选项使用 Selected，否则 All；模型非空可清理集合使用 Cleanable，否则 All。无关发布、同 generation 最终汇总及导航不覆盖用户手动选择和筛选；本模块重扫重新应用上述默认。Cleanable 是安全可选资格，不判断模型是否还有用途。首页默认队列始终排除模型，包括手动选中的模型。

Agent 显示筛选用同名计算属性解析可选的 Published 手动覆盖：自动模式按当前 Skill/MCP 类型及平台判断 Selected 是否有结果，空则 All；不使用已过滤列表反推默认，避免循环依赖。异步选择变化可更新自动默认，手动选择则保持；类型切换清理 Skill/MCP 可见缓存。过滤前只解析一次有效范围，保持线性工作量。大文件页原默认就是 All Large Files，本次没有新增或更改其范围与预选规则。

编译与版本分配：build-app.sh 在基础签名/资源/SDK预检后，以 version.py next-build 一次完成下一 patch、CI目标/单调构建号校验及原子保存；返回的两行值供同次 App/Helper 打包共用。每次运行编译脚本都会递增，普通测试、独立验证、DMG与发布不递增；已开始编译的失败号码不回滚。

上一轮资源汇总和 DMG 归属见 [实施计划](../doc/cleanup-center-resource-sync-plan.md)。ProjectArtifactScanner 识别工程内独立及构建目录内的 DMG；Git 跟踪、路径/身份和内容检查继续用于执行复验。ProjectInstallerOwnership 从大文件展示清单和树中排除已归项目的 DMG，原始候选保留以便刷新与副本保留证明校验。项目/大文件渐进结果先后不影响最终归属。项目产物不检测或展示运行状态，目录及 DMG 的选择和执行均不受活动状态限制；完整扫描保留共享探针的具体打开文件，供其它维度沿用原有活动保护。项目根待刷新时，首页排除旧项目默认项。验收与逐文件审计见 [本批记录](../Tests/cleanup-center-resource-sync/README.md)。

项目 DMG 接管大文件副本时保留 largeFileProof，并保护其保留文件及覆盖该文件的目录。项目范围变化按路径迁移已选/撤选状态，不重新勾选人工撤选；单项取消子 DMG 时同步取消包含它的目录，选中目录包含其可清理子项。分组和首页容量都按最终目录操作去重。

本轮更新见 [计划](../doc/project-installer-discovery-plan.md)。项目 DMG 发现与副本证明由 ProjectArtifactScanner 承担；大文件发布前依据同一项目根/manifest 规则排除其清单与容量树，避免临时默认数后续消失。正式 App 显式链接实际 SDK 与独立的 macOS 13 最低版本，记录 DTSDKName 并与 Mach-O 复核。删除手动标题栏背景干预，由原生 NavigationSplitView 和 unified 工具栏管理边界；不再混淆 SDK 与最低系统版本，不使用固定偏移。模型保留分类，但始终手选；证据见 [验证记录](../Tests/project-installer-discovery/README.md)。

当前布局更新：磁盘从清理中心移至 Tools 下方的侧栏底部，显示硬盘图标和“磁盘空间”标题、容量条及可用空间；继续共用 AppModel 的读取、错误与自动刷新状态，不复制数据源。侧栏和清理中心底栏共用 SidebarSurface 的不透明系统底色，跟随系统外观，避免桌面透色差异；其它维度底栏继续使用原 bar 背景。见[实施计划](../doc/dashboard-sidebar-footer-plan.md)和[逐文件验证](../Tests/dashboard-sidebar-footer/README.md)。

本轮项目选择策略见 [实施计划](../doc/project-selection-preferences-plan.md) 和 [逐文件验证记录](../Tests/project-selection-preferences/README.md)。设置切换即时更新既有结果和首页缓存，关闭仅撤销自动选择，不清空人工决定；扫描或执行期间禁用开关。Git 跟踪 DMG 使用同一手选快照边界，仍检查路径、权限、云盘、包和保护；不加入自动副本保留证明。未知 Git 状态与其它保护继续执行复验。

关闭/退出共用首页的确认工厂和执行器；关闭提醒额外显示“不再提醒”，手动及明确退出不显示。抑制只改用户偏好，成功才确认容量；退出等待及终止后去重保持。现行规则见 [关闭提醒选择计划](../doc/close-trash-reminder-choice-plan.md) 与 [原生回归](../Tests/close-trash-reminder-choice/README.md)。

应用卸载的行级分析和全量计划共用按 plan.id 缓存的 checkedUninstallPlan，首屏不强制构建所有应用计划，空选择汇总直接零。ProtectionPolicy 的批量入口只在本批复用保护根解析，每项仍检查实时物理路径，下批和执行重新解析；新报告/保护变化失效全部缓存，运行状态变化调整可执行性。见 [性能计划](../doc/application-first-entry-plan.md) 与 [基准和审计](../Tests/application-first-entry/README.md)。
# 0.4.27：模块进度与延迟关闭提醒

所有维度页复用 `ModuleProgressView`；当前模块 waiting/scanning 优先于旧结果，其它模块的完成结果仍可查看。Agent 的列表准备与能力分析提示保留。状态入口为 `AppModel.moduleScanProgressMessage(for:)`。

关闭窗口的提醒请求由 `TrashReminderController` 保留到模型可执行 Trash 操作为止，Combine 主 RunLoop 订阅只保留一份，空闲后仍调用同一个 Empty Trash 接口。保留零成功清理不提醒、抑制偏好、取消/失败不确认总量等语义。见 [计划与证据](../doc/module-progress-trash-reminder-plan.md)。
发布源合并父模型与 Helper；仅关闭请求会在执行结束后用原 dismissDeletionSheet 解除已隐藏结果的门禁，不中断执行或删除历史。
# 0.4.30 关闭提醒与清空

只读扫描期间可直接确认并执行清空，现有扫描继续。执行本身/结果呈现等互斥保持；同一资格和锁决定是否显示确认，工厂只决定关闭 checkbox，不接受禁用清空的参数。见 [计划与并发证据](../doc/trash-during-scan-plan.md)。

## 0.5.0 发布版本分配

常规构建继续自动递增 patch/build；显式 `build-app.sh --version <version>` 在同一分配入口验证目标严格增加，精确使用目标展示版本并递增 build。校验完成后才原子保存，App、Helper、验证及 DMG 复用同一份 [Version.json](../Version.json)。本轮汇总六模块、项目与本地模型、统一扫描提示、Trash 生命周期及界面调整；见 [发布记录](../doc/release-0.5.0.md)。

本地模型逐模型选择、共享引用、独立恢复快照和失败清理边界见 [现行模型架构](../doc/architecture.md)、[现行架构](../doc/architecture.md) 及 [模型清理回归源码](../Tests/CleanerCoreTests/OllamaModelCleanupTests.swift)。模型不检测运行状态，沿公共删除与恢复流程执行，无新增依赖。

当前本地交付为 [0.5.17（162）](../doc/release-0.5.17.md)，已安装并启动于 `/Applications/SuperCleaner.app`；安装副本逐文件及符号链接核对通过，沿用原签名身份。本轮直接安装已验证的 App，没有生成新 DMG。

Helper 与切回应用的性能边界见 [激活路径审计](../doc/helper-activation-audit.md)：普通激活只查询注册状态，不发起 XPC 文件操作；已授权会话的系统校验仍有主线程风险，不能由未授权状态自检推断整条激活链路无阻塞。当前开发安装包的 Helper 未启用，偶发转圈尚未复现并归因。

应用重新激活不再触发磁盘容量读取或由此产生的共享 AppModel 发布；启动/窗口重建、扫描启动、清理和恢复/历史刷新、清空废纸篓后的容量更新继续保留。运行应用与权限的必要刷新沿原路径执行。该单一触发点移除用于对比偶发卡顿，尚不代表已确认或解决全部卡顿。

项目产物的运行状态不参与扫描、选择或执行资格判定，项目单模块刷新与执行不请求活动数据；完整扫描保留其它来源需要的共享探针。

项目产物对单个纯公钥 PEM 不再触发凭据保护；SwiftPM `.build` 内有工作区状态记录的远程依赖副本不触发嵌套仓库保护，仍遍历其内容计量并检查凭据。真实私钥、环境凭据、非托管或 edited 仓库继续保护。

项目页和默认项目候选通过同一展示投影隐藏可清理父目录内的 DMG 平铺行，保留根目录安装包和受保护目录中可独立清理的安装包。原始记录仍用于归属与复验；当前保护应用后再投影，目录选择迁移到大文件时保留其子路径决定。

侧栏按用户要求只显示当前磁盘容量条和可用空间，不再显示本次启动以来的增减值；变化基准、派生计算、专用检查及双语提示均已删除，现有容量读取和失败展示继续保留。

## 系统清理展示分区

[GuidedCleanupView](../Sources/CleanerApp/GuidedCleanupView.swift) 首先按建议清理/深度清理（Deep Cleanup）分组：建议清理统一汇总并默认展开，深度清理统一汇总并默认折叠；深度清理仅为原建议保留组的标题更名，候选分类与默认选择保持；每个建议组内直接并列 System 和具体应用，没有 Applications 中间层；明细初始折叠。复用历史版本的应用归属分组，已知应用显示名称，没有归属信息的项目进入 System，按容量排序。应用缓存和日志恢复 0.3.30 的推荐资格；共享缓存、离线内容及微信聊天文件仍需手动选择，扫描保护和执行复验保持。历史证据与验证见 [修复说明](../doc/disk-refresh-system-groups.md)。
