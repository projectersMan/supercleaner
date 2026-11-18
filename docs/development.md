# SuperCleaner 开发指南

## 环境与构建

全扫描用时只记录在AppModel，不从最后一个模块报告时间推断；须等待系统、应用、重复大文件、Agent、本地 AI 模型、项目产物六模块和Agent分析均结束。Dashboard用局部TimelineView每秒显示HH:MM:SS，停止后静态展示；计时位于按钮右侧，等宽数字防止抖动。全扫描启动后的必要预访问计入本轮、重扫归零、取消/失败冻结、继续同轮沿用起点，完成后的单模块刷新不改写上一轮全扫描用时。计时不得修改扫描任务、权限、清理或覆盖分析规则。

图标视图直接显示同步缓存结果，避免State初始nil与出现后的task导致占位图逐个替换；不引入新预加载服务或持久图标缓存。图标排查先核对NSWorkspace返回值与包中图标声明。不能仅因缺CFBundleIconFile就覆盖asset catalog或自定义图标；仅系统通用图标允许沿真实包路径回退，优先最近外层应用，不做Bundle ID前缀猜测。外层包以APPL元数据识别，不能仅判断.app后缀；WorkBuddy的.app.installing临时包是已复现的真实案例，非标准目录直接读取包声明图标。定向复现命令：`zsh Tests/application-icons/run-check.sh`，需本机已安装WorkBuddy；缺夹具返回77，不计为通过。

本地交付统一覆盖/Applications/SuperCleaner.app，退出非清理中的旧实例、验证新包后替换并从固定路径启动；保留应用支持目录与偏好设置。不要从build产物再启动第二个安装副本。

Dock reopen优先把最小化的主窗口逐一deminiaturize；若窗口已被红色关闭按钮关掉，则通过带`main`标识的WindowGroup和SwiftUI`openWindow`重新创建主窗口。两种情况都返回false，阻止AppKit默认行为覆盖显式处理；已有可见窗口时返回true。

清理后关闭提醒只读取本次累计清理量，并由窗口关闭和退出路径共用一个状态；0 字节、已确认容量、永久关闭提醒不弹窗，新增清理可再次提醒。不要替换 SwiftUI 的窗口 delegate 或监听所有面板，不得未经用户永久删除确认就清空废纸篓。原生弹窗和持久化验证见 [关闭提醒计划](../doc/trash-close-reminder-plan.md)，相关素材统一放在 [Tests/trash-close-reminder](../Tests/trash-close-reminder)。

首页显式清空按钮由同一个 TrashReminderController 实现；确认永久删除后再异步调用固定 Finder 命令，成功且实际已空才记录启动时累计量。取消/失败不确认，原 suppress 偏好不能被重置；结束刷新并等待容量读取完成。清空忙碌门禁必须覆盖模型执行入口、更新/退出及界面，不能只禁用按钮。只增加 Apple Events Automation entitlement 与本地化用途描述；不直接 rm Trash。验证使用假执行器，实机只走确认取消，详见 [本批计划](../doc/dashboard-compact-trash-plan.md)。

清理中心UI约定：六行只保留整行导航与最右对齐状态，不把模块取消/继续重复放在首页；内部DimensionActionBar必须仍能操作当前模块。悬停色与应用卸载保持accentColor/0.08，移出恢复。completed/limited在首页共用绿色勾选“扫描完成”，不得反向修改原始扫描状态、覆盖证据或删除保护。三张能力卡以最高内容自适应等高，保持顶部对齐；不要按某种语言的当前行数硬编码高度。

首页压缩为单页，扫描按钮下显示用时，与紧凑容量、累计清理/清空按钮同行等高；不得仅隐藏滚动条而裁切内容。中英文本、detail 760×560 pt 和默认窗口均检查六行导航与头部能力卡可见。大标题/说明缩小，长说明通过单行与 tooltip 保留。

顶部扫描与累计清理区域不使用容器背景或边框，保持原生按钮与安全卡样式；按钮尺寸及对齐按本批截图调整，不修改扫描规则。

扫描启动排查：全扫描直接开始，不能重新引入大权限配置sheet或逐次确认。首次必要的只读预访问在并行模块启动前执行一次；不因已提醒标记推断权限可用，不自动改写系统授权。

Agent分析排查：先核对安装包版本与源码版本，再检查索引modelVersion/analysisVersion和现行policy指纹。策略不兼容必须给出直接可见的状态；不能只更新tooltip，也不能通过降低85%预选阈值或0.95片段门槛制造结果。行内覆盖组件独立为AgentContainmentLabel，以真实Gemma夹具和渲染对照验证Top 3、累计覆盖及保留覆盖来源的预选规划。

扫描授权偏好：不要把实际权限拒绝转换成空读取或篡改所有权覆盖；记录已发生的拒绝并在GUI投射为可访问范围完成。禁止靠错误文案匹配或把所有access类错误都隐藏。配置读取失败、数量/深度/时间/格式等非权限问题仍保留。App的数量上限策略必须传入各子扫描器，不能只修改首页入口数字；执行上下文仍使用原始约束，取消逻辑持续有效。

权限交互要求：首次启动仅对尚未验证FDA的用户显示一次简短提醒；已有FDA用户跳过，之后重启和扫描不重复弹App配置窗口。UserDefaults的introductionShown和scanAccessRequested只记录提醒/请求次数，绝非TCC授权。设置保留系统入口，真实访问状态由PermissionStatusService/执行结果确定；不试删验证App管理，不申请辅助功能、录屏或输入监控。

应用行的正常分析完成状态不显示徽标；隐藏逻辑仅位于ApplicationsView展示层，不修改Core状态或statusTitle，以保留其他调用方语义。系统保护、运行保护、受限、不可用和等待状态继续展示。

界面布局约定：应用卸载与[重复大文件页](../Sources/CleanerApp/DiskSpaceView.swift)共用原生分段控件。在[ApplicationsView](../Sources/CleanerApp/ApplicationsView.swift)固定搜索260 pt、分段420 pt、排序/数量各140 pt；[ApplicationScopePicker](../Sources/CleanerApp/ApplicationScopePicker.swift)使用原生等分分段控件，纵向按固有高度。窄窗口用ViewThatFits分两行，切换四个选项、计数变化都不能改变同一窗口中的控件位置。两页标题间距、栏内边距和字号保持一致。

- 平台：macOS 13 或更高版本。
- 语言与 UI：Swift 6、SwiftUI、AppKit。
- 包管理：Swift Package Manager；应用更新使用固定版本的 Sparkle。
- 推荐使用与目标 SDK 匹配的完整 Xcode。仅有 Command Line Tools 时，脚本会选择本机兼容 SDK，但 XCTest 可能不可用。

常用命令：

```bash
./Scripts/build-app.sh
./Scripts/verify-app.sh
open build/SuperCleaner.app
```

`build-app.sh` 在正式编译前自动分配一次新版本，构建核心契约、主 App 和 Helper，并组装本地 App。`verify-app.sh` 检查 Bundle、资源、Helper、最低系统版本和签名，并在系统临时目录执行真实隔离/恢复烟雾测试。

Agent能力分析规格见[分析设计](../doc/agent-skill-overlap-analysis-design.md)。根包、App与Helper保持macOS13要求；AgentInference独立SwiftPM包仅面向macOS14/arm64，固定GemmaEmbed0.4.1，由AgentOverlapAI通过本机stdin/stdout调用。模型及SDK许可随App打包，模型固定大小/SHA-256由脚本校验。Agent分析仅在支持的平台启用，本地模型库存扫描不依赖该推理进程；六维度仍使用原有删除/文件恢复与发布门禁，本批未新增依赖。

覆盖排名取其他同类对象前3名，并展示路径；累计分母使用全部提取能力描述，来源取去重并集，默认85%（含85%）预选，前3只是展示。既有对象/零关系按稳定身份复用，只有新增项补算；策略变化要求设置中显式重算。Skill/MCP使用同一规划及基线安全资格，保留覆盖来源与用户明确保留。分析不二次打开manifest，不连接MCP或读取凭证/参数。

修改须逐文件、逐函数核对，保留用户历次明确授权的Agent功能、首页布局固定、六行导航、标题栏对齐、模块独立取消/继续扫描及必要依赖、打包、版本和文档。独立CLI已按本批授权删除，不恢复其参数解析或JSON传输层；规则、保护、覆盖与只读行为继续由直接Core契约验证，Helper和发布门禁保留。模块回调同时检查generation和单次运行令牌；Agent扫描期间的嵌入任务属于Agent模块取消范围。继续扫描重跑单个模块并保留同批其他结果，不能替换成整批重扫。历史核对记录见[范围审计](../doc/agent-only-scope.md)，本批范围见[六维度实施计划](../doc/local-ai-projects-disk-plan.md)。

### 本地模型、项目产物与卷容量

[LocalAIModelScanner](../Sources/CleanerCore/LocalAIModelScanner.swift) 集中维护七类供应商的十个固定根、布局和执行复验。Hugging Face 以仓库为单元、LM Studio 以 publisher/model 为单元、Ollama 整库；Keras 限 models/datasets，GPT4All 限识别出的模型文件。不得把整个工具支持目录纳入清理，或把共享 blob 当作单独模型。验证候选和祖先无链接；内部链接不跟随、不重复计量。Core 候选保留显式选择标记，模型页始终要求手动选择并确认，不预选；项目页的自动勾选由设置开关控制，初始关闭，开启后包括通过检查的 Git 跟踪项。活动未知/运行/凭据/权限/预算保守拒绝；执行时重新验证范围、身份、大小和元数据指纹。指纹证明扫描快照的一致性，不应描述成全模型内容哈希。

安全验证调用与是否允许内容变化解耦：模型目录和文件都严格拒绝变化，不能用 `allowsExecutionContentChanges` 同时控制是否调用最终验证。回归须覆盖初始验证之后、实际移动之前，以及公共执行器 Helper 拒绝处理而回退用户态后的终验；期间内容、活动或保护状态变化必须拒绝移动。不能只测文件身份变化而遗漏目录或等待边界。

[ResourceCleanupView](../Sources/CleanerApp/ResourceCleanupView.swift) 使用与应用/大文件一致的 260pt 搜索、范围、排序和数量栏，窄窗口分行；模型按 `LocalAIModelProvider`、项目按 `project-root` 展开全宽分组，详情按需显示。全选/组选择只处理可见且可清理项，继续调用 AppModel 选择入口；筛选不丢选择，不影响其它维度，模块 limited 不等于所有已验证项目不可选。两个资源页均移除页头操作按钮。项目使用已有 [ProjectArtifactScanner](../Sources/CleanerCore/ProjectArtifacts.swift)，根目录由 `NSOpenPanel` 多选并经 `ProjectScanRootsStore` 保存；已有报告时仅刷新项目模块；设置无报告时只保存，首次全扫描从清理中心沿原权限准备流程启动，回归必须覆盖这些分支。项目由 manifest 识别；Git 跟踪内容可手选，项目自动勾选须由设置开关开启；未知 Git 状态、嵌套仓库目录、凭据、活动与读取失败保护不能因 ignored 或目录名被放开。模型和项目都不进入系统默认队列和Agent包含率预选。

修改维度须同时覆盖 `ScanModuleID`、`CandidateSource`、导航、report payload、Coordinator、AppModel的启动/取消/继续/渐进合并、scope/default selection、执行验证和清理后跨模块对账，禁止仅新增页面却遗漏执行入口。六个模块结果彼此独立，旧 generation 或旧运行令牌不得回写。

[DiskCapacitySnapshot](../Sources/CleanerCore/DiskCapacitySnapshot.swift) 使用 `statfs` 的卷总量及当前用户可用量，已用为两者之差，不加 estimated purgeable。AppModel 异步刷新并公开失败状态，侧栏不能用 0 或旧快照掩盖读取失败。验收覆盖激活、扫描和清理后的自动刷新，候选逻辑字节和回执累计量不得充当物理释放量。相关夹具、脚本与日志集中放在 [Tests/local-ai-projects-disk](../Tests/local-ai-projects-disk)，最终测试数量和包验收事实以实际日志为准。

### 语言与版本管理

设置页提供 English 和中文（简体），首次启动以及无效偏好均默认英语，不跟随系统语言。选择保存在应用偏好 `appLanguage` 中，下次启动生效；界面会提示先完成当前操作再退出重开。语言切换不重建扫描模型、不丢弃当前选择，也不会中断执行。

`CleanerCore/Localization.swift` 在进程启动时固定本次语言，后台扫描和界面共用它。自有界面与诊断文案维护在 `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings`。参数使用 `{0}`、`{1}`，允许翻译调整顺序，但不会重新解释文件名和路径中的占位符。文件名、用户 Skill 文档、第三方规则及历史记录中的原始内容不做自动翻译。原有卸载归属判断使用的标准证据字符串保持不变，仅翻译展示副本；Skill Markdown 的中英文标题识别也保持不变。系统权限说明位于 `Resources/{en,zh-Hans}.lproj/InfoPlist.strings`。

版本的唯一仓库配置为根目录 `Version.json`，包含三段式 `version` 和递增正整数 `build`。每次运行 `build-app.sh`，在签名、模型资源与 SDK 等基础检查通过后、第一次 Swift 编译前调用一次 `version.py next-build`，自动将第三位和构建号加一（如 `0.0.9` → `0.0.10`），打印并保存这次使用的值。第一位和第二位只按人类明确要求修改，不自动进位或重置。Info.plist 源文件中的零值只是打包占位符；同一次分配的版本供主 App 和 Helper 共用。设置页读取实际安装包元数据；未打包程序显示“Unpackaged”。

```bash
python3 Scripts/version.py show     # 查看，不修改
./Scripts/build-app.sh              # 内置自动递增，不要先手动 bump
python3 Scripts/version.py resolve  # 只读解析；供验证/发布使用
```

重复执行编译脚本也会再次递增；这是用户最新要求，取代旧的“每修改批次手动递增一次”。普通测试、`verify-app.sh`、`create-dmg.sh` 和 `publish-release.sh` 不递增。基础检查或版本参数校验失败不写入新版本；已分配版本并进入编译后发生失败则保留该号码，下次编译再分配新号码，不回滚或重复使用。`version.py bump` 仅保留作显式维护命令，正常构建无需调用。

CI 可选 `SUPERCLEANER_VERSION` 必须等于本次分配的展示版本；`SUPERCLEANER_BUILD_NUMBER` 如提供须严格大于旧配置构建号，并随实际版本写回 `Version.json`，保证随后不传环境变量也能解析同一版本。后续验证/发布中的环境值须与已分配版本一致；重复构建需提供新的 CI 值或移除覆写。普通递增拒绝 major、minor 和仅增加 build；人类明确指定发布版本时运行 `./Scripts/build-app.sh --version 0.5.0`，目标必须严格大于旧展示版本，直接使用 0.5.0 并增加构建号，后续普通编译恢复 patch 递增。正式发布仍需真实的 `SUPERCLEANER_PREVIOUS_BUILD_NUMBER`，发布构建号必须更大；版本管理不自动发布或上传。

```bash
python3 -B -m unittest discover -s Tests -p 'test_version.py'
python3 Scripts/check-localizations.py
```

构建时自动检查双语键、参数和内置规则说明的覆盖。核心契约验证语言默认值、偏好持久化、参数保护和实际包版本读取；打包验证分别以英语和中文检查资源，并核对主应用与 Helper 版本一致。

`SUPERCLEANER_BUNDLE_ID`可设置正式主应用标识符，Helper标识符、Mach service、LaunchDaemon名称和BundleProgram从同一值生成。主App、Helper及AgentInference使用显式签名标识符；Apple签名启用Hardened Runtime与时间戳，本机开发身份使用本地签名模式。独立CLI的构建、复制、签名和required identifier已移除。构建门禁验证`--self-check`：开发/示例Helper必须退出78，不能启动listener；正式身份检查不安装、注册或弹授权UI。

Helper 通过设置页显式注册，需放在 `/Applications`，并由系统管理员批准。再通过“验证连接并授权本次会话”开启最多 5 分钟受限操作。升级后可重新注册，先异步解除旧注册再安装本版本。恢复区内容与注册无关，移除 Helper 不清除内容；会话过期时需要权限的自动清除会失败并保留内容，不自动弹管理员授权框。

### 固定签名与重复授权

`Scripts/signing-identity.sh`只读选择签名身份：优先显式`SUPERCLEANER_SIGN_IDENTITY`，然后读取`~/Library/Application Support/SuperCleaner/Signing/identity.sha1`固定指纹，未配置才寻找Apple证书。默认要求有效证书，缺失即失败，不自动改为ad-hoc；指纹已固定时也不会改选其他证书。证书和私钥存于登录钥匙串，私钥不写入仓库、App或DMG。本机自签以代码签名用途信任，由用户本人确认；它保持证书绑定DR（系统对本机自签身份生成certificate leaf指纹形式，Apple身份通常为anchor形式），不依赖每次构建变化的cdhash，但不具备Apple公证发行身份。

构建脚本的`--mode`区分Apple身份与本机开发身份；本机开发签名不申请Apple时间戳、不启用依赖Apple团队的library validation，生产门禁继续要求Developer ID、同团队、Hardened Runtime、时间戳和精确标识，并包含AgentInference。只有明确传入`SUPERCLEANER_REQUIRE_STABLE_SIGNING=0 SUPERCLEANER_SIGN_IDENTITY=-`才允许临时检查包，不用于固定安装交付。验证稳定性应对内容不同的两个产物比较DR，并以旧DR检查新产物；单纯重复签相同二进制不能证明跨构建稳定。

要避免无意生成临时签名版本，使用严格模式：

```bash
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/verify-app.sh
```

缺少可用证书时，严格构建在编译和替换现有 App 之前停止；显式配置的证书失效时也直接停止。安装证书后建议使用同一个证书 SHA-1 固定后续构建身份：

```bash
SUPERCLEANER_SIGN_IDENTITY='证书 SHA-1' SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
```

证书可以从 Xcode 的 Settings → Accounts → Manage Certificates 创建 Apple Development 身份，或导入已有 Apple Development / Developer ID Application 签名身份（必须包含私钥）。脚本不会生成证书、修改钥匙串信任或修改系统隐私数据库。首次从临时签名切换到固定证书后，退出 App，在系统设置 → 隐私与安全性 → 完全磁盘访问中重新添加当前 App，然后重启；App 管理权限在实际卸载需要时由系统确认。应持续使用同一证书和 Bundle ID，以保持授权身份兼容。

依据：[Apple 代码签名身份与隐私授权](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)、[Xcode 管理签名证书](https://help.apple.com/xcode/mac/current/en.lproj/dev154b28f09.html)。

### 卸载分析的局部失败

应用本体身份可验证时，大小统计中的单个文件错误只产生带路径和原因的 `ScanLimitation`，不丢弃整个卸载计划。无法完整检查的关联项保持 `blocked`；用户数据和共享目录不递归读取，仅展示为“未统计”。本体大小不完整时标记估计值；本体身份无法验证时仍拒绝生成计划。`LocalFileSystem.identity` 读取链接自身元数据，不使用会跟随链接目标的存在性检查，避免 Electron `SingletonCookie` 等失效链接导致整个分析失败。

仅对指定应用执行真实只读复现（按应用已退出的条件构建计划，不执行卸载）：

```bash
swift run CoreContractChecks --check-installed-uninstall '/Applications/Example.app'
```

## 开发原则

1. 扫描必须只读，递归扫描必须限制深度、条目预算并响应取消；若为 Skill 目录建立索引，只能受限读取 `SKILL.md` 头部内容；MCP 摘要只能保留服务器名称、传输类型和项目归属，禁止把命令参数、env、headers、token、secret、源码、凭证或普通知识内容带入展示模型。
2. UI 选择与列表焦点分离；受保护项目不得通过 UI 或状态恢复进入计划。
3. 所有写入只能来自不可变 `CleanupPlan` 的真实执行。
4. 确认界面不产生文件系统副作用；`CleanupExecutor` 必须在写入前重新检查计划时效、规则版本、路径、活跃状态和文件身份。
5. 删除优先进入 App 自有隔离区；恢复不得覆盖已有路径。
6. 执行、恢复和彻底删除的意图日志必须先于文件副作用持久化；历史和调度完成后才能移除日志。
7. 同一 `planID` 只能由协调器执行一次；重复计划必须在写日志和文件副作用前失败。
8. 同一 receipt 的待执行日志复验、恢复、彻底删除、自动维护和重新调度必须共享生命周期互斥；复验获得互斥后及历史提交前必须读取最新回执，复验不得覆盖已有保留策略与重试元数据。
9. purge 日志记录准备时源存在后，恢复时源缺失应收敛为已彻底删除；准备时已缺失则保持未验证失败。
10. resolution 结果未全部进入对应终态时必须保留 journal，不得错误清除恢复依据。
11. 自动清理成功状态必须按标准化路径而非单个 UUID 清除跨模块别名。
12. 新增规则必须更新 [`docs/rule-sources.md`](rule-sources.md)，包含来源、独立验证、测试夹具和责任人。
13. 扫描态的删除资格按当前模块结果与既有执行门禁判断，不能仅靠UI禁用；模块扫描控制契约必须覆盖六个扫描维度。维度底栏必须优先展示当前模块扫描状态；应用卸载与普通候选执行期间均需提供进度、停止后续项目入口并禁用重复确认删除。失败项重试遵循既有扫描互斥。

## 执行生命周期开发要求

`CleanupExecutionCoordinator` 是执行事务边界：

```text
写入 execution-journal.json
  → CleanupExecutor 真实复验并隔离
  → 写入 history.json
  → 写入 quarantine-schedules.json
  → 删除执行日志

写入 resolution-journal.json（恢复/彻底删除）
  → 按日志中的稳定源/目标执行或启动复验
  → 更新 history.json
  → 协调 quarantine-schedules.json
  → 仅在全部项目进入对应终态后删除 resolution 日志
```

修改此链路时至少验证：

- 日志写入失败时没有文件移动；
- 执行中断后能按源路径/隔离路径真实状态恢复；
- 同一 `planID` 重复提交时在文件系统副作用前失败；
- 恢复/彻底删除日志写入失败时没有文件移动或永久删除；
- 恢复/彻底删除在文件副作用后写历史失败时能由启动恢复完成；
- 历史已成功而调度失败时，不会重复移动文件；
- 恢复与彻底删除只能访问回执拥有的隔离路径；
- 同一 receipt 的恢复、彻底删除、自动维护和重新调度不会并发修改，等待者基于最新历史决定后续动作；
- purge 准备时源存在且恢复时缺失，应提交 `permanentlyDeleted`；准备时源已缺失则保持失败；
- 任一恢复/彻底删除结果未解决时保留 resolution journal；
- 自动清理成功后按标准化路径清除跨模块选择、默认队列和旧失败状态；
- 原子提交失败不会破坏上一版历史或调度。

审计修复的定向回归入口为 `CoreContractChecks --check-review-recovery`、`--check-ownership`、`--check-review-coverage` 与 `--check-review-expiry`，默认全量契约同样执行它们。使用受限临时目录、内存文件系统和可控时钟，覆盖后台复验与恢复/清除/调度交错、管理来源变化后的旧关联项、Agent深目录及读取限制传播，以及五个异步边界过期；不注册 Helper、不访问真实用户清理目标。`--check-core-read-only` 直接调用Core验证分类、显式/默认计划、空历史、文件/mtime不变及保护清单的精确拒绝；不再要求CLI参数或JSON传输契约。

## 自动删除失败与重试

到期隔离项由 `QuarantineMaintenanceCoordinator.processDue` 处理。单项未成功彻底删除时：

- 内容继续留在隔离区，历史仍保持可恢复状态；
- 调度记录写入 `AutomaticCleanupFailureReason`，包含错误码、消息和失败数量；
- `lastAttemptAt` 记录最近尝试时间；
- 历史提交前先持久化本次尝试；历史写入失败时保留 `historyPersistenceFailed` 结构化原因；
- `dueSchedules` 默认至少间隔 1 小时才再次返回该失败调度；
- App 运行时每 60 秒轮询到期项，关闭期间不运行后台常驻服务，重启后补偿。

变更重试策略时，应同时覆盖成功、部分失败、全部失败、缺失历史、已无隔离内容和重启补偿场景。

## 当前集成限制

### 公开发布配置与规则协议

`Resources/release-configuration.example.json` 是故意不可发布的模板。只填写正式 Bundle ID、Team ID、公开 Ed25519 公钥及 HTTPS 源；不得加入私钥、密码、公证凭据、Cookie、header 或带 token 的 feed query，未知字段会被拒绝。通过 `SUPERCLEANER_RELEASE_CONFIG=/绝对路径/public-config.json` 显式传给构建脚本；未设置时不会嵌入示例或启用网络更新。配置中的 Bundle ID 派生 App / Helper / AgentInference 标识符，若环境另设不同 ID 则构建失败。此配置校验不是证书、公证或线上发布验收。

规则更新接口为 camelCase 的 `SignedRuleUpdate` JSON：`packData` 是原始 RulePack JSON 字节的 base64，`signature` 是对这些精确字节进行 Ed25519 签名后的 64 字节 base64。RulePack 的日期沿用 Swift JSONEncoder 的 2001-01-01 UTC 参考秒数；展示层的格式化JSON不得混作签名输入。`activationID` 属于本地状态，发布包必须省略；签名不是对 executionVersion 字符串计算。

发布包 `issuedAt` 必须高于已见最高包和当前随包基线，并且不能超过本机时钟 10 分钟；重复的当前原始包可作无变化检查，显式回滚后的最高包重放也会拒绝。建议发布者持续携带累计 revokedRuleIDs，接收端保存并复验历史签名证据；证明数量上限 64、单包 1 MiB、网络 envelope 1.5 MB、状态 8 MiB，超过限制拒绝更新而非丢弃撤销。新版 App 随包撤销也会与已安装包合并。HTTP 源应返回完整原始内容并尊重 `Accept-Encoding: identity`。

`CoreContractChecks --check-updates` 覆盖真实 URLSession delegate 的代送 HTTP 响应、重定向、大小/时间/取消限制及完整签名规则流程。打包门禁改用 `--check-packaged-rule-config /绝对路径/SuperCleaner.app`：复制契约工具自身和实际打包Core资源进入临时Fixture.app，直接验证公开配置、资源定位和已安装签名规则生效，且不创建历史或改写规则状态。该检查保留固定配置和签名规则门禁，不依赖已删除的用户CLI，也不证明实际发布主机的TLS、证书或可用性。

- 卸载图契约覆盖不同名称副本、签名应用组、独立 Label 的显式服务引用、二进制 plist、配置去敏、Homebrew/Steam 交回原渠道、真实临时 BOM 和旧计划复验。`CoreContractChecks --check-ownership` 可单独运行。系统关联文件始终保护；挂载卷应用只参与归属，不可直接删除。

- Helper：安装/异步移除、系统批准、双向签名 XPC、显式管理员会话和受限应用文件操作已接入主 App。`CoreContractChecks --check-helper` 验证无链接路径、UID/plan/身份、授权、移动恢复清除、预算、执行路由与迟到完成恢复；打包 self-check 仅检查身份，不注册或调用特权操作。真实安装/授权/连接仍须正式配置及干净 Mac；ad-hoc / 示例身份必须拒绝启动。
- 规则：签名网络分发、离线导入和回滚已接入设置页，生产扫描通过 `CleanupRuntime` 使用当前包和发布公钥，直接Core契约保留该配置验证。执行身份含结构化摘要与激活 ID，必须随计划传递并在执行前重新加载。撤销与 high-water 不能随回滚丢失；禁止恢复固定 `bundled-1` 的生产路径。
- 发布：脚本默认要求有效固定证书，缺失即失败。即使本机开发签名验证通过，也不能证明Developer ID、公证、staple或Gatekeeper发布链完成。

### 应用更新与发布脚本

应用 feed 使用 Sparkle 2.10.0 的签名 appcast XML，不再发布旧 JSON manifest。`applicationPublicKey` 是 Sparkle Ed25519 公钥的原始 32 字节 base64；构建将 URL / 公钥写入 SUFeedURL / SUPublicEDKey，公开配置与 Info.plist 必须一致。依赖版本、源码 revision 与二进制 checksum 固定；App 中保留 Sparkle LICENSE。无需把 Sparkle 的私钥放进配置或仓库。

运行更新是显式用户行为。检查前解除 Helper 注册；取消、下载/安装失败或升级后，都需按需在设置中重新启用。准备期间扫描/清理/恢复被锁定，普通退出被阻止；最后确认立即安装后才允许退出。SDK 承担文件替换及旧版本恢复，实际特权安装、崩溃/断电行为尚须干净机验证；这不是启动后健康探测或自动降级系统。修复有问题的正式版本应发布更高构建号，不能重放旧构建。

发布环境需显式提供以下变量（均为路径、公开身份或 Keychain 中的名称，不是密码/私钥）：

- `SUPERCLEANER_RELEASE_CONFIG`：完整公开 JSON 的绝对路径。
- `SUPERCLEANER_SIGN_IDENTITY`：Developer ID Application 证书名称或 SHA-1。
- `SUPERCLEANER_VERSION`：构建时如提供，必须等于本次分配的目标版本（普通 patch 递增或显式 `--version`）；后续发布时须与已写入 `Version.json` 的版本一致。`SUPERCLEANER_BUILD_NUMBER` 如提供须大于旧构建号，实际值写回配置；未提供则旧号加一。
- `SUPERCLEANER_PREVIOUS_BUILD_NUMBER`：上次正式构建号；首次发布为 0。必须从真实发布记录取得，门禁不能证明这个人工输入正确。
- `SUPERCLEANER_NOTARY_PROFILE`、`SUPERCLEANER_SPARKLE_ACCOUNT`：已有公证 Profile / Sparkle Ed25519 Keychain account；脚本不创建或导出私钥。

先构建、验证，再运行 `./Scripts/publish-release.sh --preflight`。它是只读本地检查，严格拒绝开发 / ad-hoc 签名、错团队、缺少 Runtime/时间戳和不安全 entitlements；不验证私钥或公证凭据的可用性。本地 ad-hoc 构建为加载无 Team ID 框架而不启用 Runtime，不添加禁用 library validation 的 entitlement，且绝不能越过正式发布门禁。

只有显式 `./Scripts/publish-release.sh --publish` 才创建新 `build/releases/<version>-<build>/`。脚本复制已签名 App，调用 `create-dmg.sh` 生成包含 App 与 `/Applications` 快捷方式的只读 DMG，使用同一个 Developer ID Application 身份签名 DMG，再提交 notarytool 并检查 Accepted、staple/validate 和 Gatekeeper，最后用该 DMG 生成签名 appcast。公开公钥门禁再次检查 feed/归档签名、build、OS、主机和长度。任一步失败保留 staging 供排查，不产生 `LOCAL-GATES-PASSED`，不覆盖旧发布、不自动重试。成功也仅表示本地发布门禁通过：完成干净机验收后，人工上传 `public/` 内 DMG，最后原子切换签名 XML。不要上传 notary 日志、staging app 或密钥。

更新 DMG / appcast 必须保持原始字节，不允许 CDN 改写 XML、HTML 压缩或重新制作镜像。发布源为 HTTPS；当前配置和自动生成 feed 都不使用带 token 的 URL。应用传输由 SDK 管理，逐跳主机和网络预算策略不能直接套用规则更新的测试结论。SDK 的 Ed25519 信任链允许证书轮换；同团队和公证检查位于本项目发行门禁，不能误写成 SDK 强制每次同团队/公证。默认仅构建当前架构，其他架构必须分别构建/验收，appcast 会标明硬件要求。

构建门禁使用随机临时测试密钥证明 Sparkle 官方 sign_update 与本项目公钥验证器互通、篡改拒绝；测试不会读取用户 Keychain。打包 App 的 `--update-self-check` 验证实际框架加载、最终确认/取消和退出保护，不启动更新器、不联网、不注册 Helper。它们不是已完成真实升级的证据。

依据：[Sparkle 发布指南](https://sparkle-project.org/documentation/publishing/)、[安全与自动更新设置](https://sparkle-project.org/documentation/customization/)、[固定 2.10.0 源码](https://github.com/sparkle-project/Sparkle/tree/2.10.0)。升级 SDK 版本必须重新核查签名 feed、准备/恢复安装和取消语义，并运行本项目的打包门禁，不能只改版本号。

## 验证顺序

面向官网、GitHub 或其他 HTTPS 渠道的站外正式发布，使用 [`production-release-checklist.md`](production-release-checklist.md) 逐项验收；该流程不涉及 Mac App Store，但要求 Developer ID Application、公证、Sparkle 签名和真实公网下载测试。

1. 运行 `git diff --check`，排除空白和补丁格式问题。
2. 运行 `./Scripts/build-app.sh`。
3. 运行 `./Scripts/verify-app.sh`。
4. 在完整 Xcode 环境运行 `swift test`。
5. 审查 `git diff --name-only`，确认改动范围符合任务约束。
6. 发布前使用正式 Bundle ID、Developer ID 和 Hardened Runtime 归档，完成公证与 staple，并在干净 Mac 验证 Gatekeeper、升级、Helper 安装/移除及权限降级。

## 文档维护

- [`README.md`](../README.md)：面向使用者，说明能力、数据流程、运行命令和发布边界。
- [`docs/architecture.md`](architecture.md)：记录模块责任、运行时数据流和当前接线状态。
- 本文件：记录开发约束、验证方法与发布门禁。
- `docs/superpowers/` 与 `docs/verification/`：保留历史设计和阶段证据；实现变化后必须添加现态说明，不能把历史结论继续描述为当前能力。
- Agent 环境若调整 Skill 主视图、目录辅助视图或逐条删除决策能力，必须同步更新 README、Dashboard 文案和架构文档中的“只读边界”“逐条显式选择”与“默认不自动清理”表述，避免把 manifest 头部解析误写成“完全不读文档内容”，也避免把 Agent 环境误导成默认清理模块。
- Agent 一级目录分组不再维护外部注册表，必须统一通过 `AgentCatalogRegistry.swift` 中的推断逻辑演进；新增推断规则时优先增强“固定根目录 + 真实文件夹 + Skill Markdown 标记”的识别顺序，不要把规则散落到多个页面文件中。
- Codex、Claude 等供应商的 Skill/MCP 文件系统位置必须统一维护在 `AgentResourcePathRegistry.swift`；MCP 格式识别与去敏解析统一维护在 `MCPConfigurationCatalog.swift`。更新规则时同步修改官方来源研究记录和 Agent scanner contract，禁止在 View 或 Adapter 中重新散落路径字面量。
- 修改大文件或 Agent 扫描时，必须同时检查 Spotlight 快速路径、精确递归回退路径和生产预算；不能在 Spotlight 已成功后无条件再次递归扫描整个 Home。
- 重复大文件在同一个模块任务中依次发现、查重、核验 ZIP，再用共享的格式表识别剩余安装文件。修改该链路时运行 `swift test --filter DuplicateLargeFileTests`，覆盖两种发现入口、安装包预选开关、保留路径冲突、受保护和活跃安装包、ZIP 同级文件夹总大小和结构筛选、小成员内容核验、保留路径变化和恢复。设置持久化和刷新、默认范围、排序与筛选隔离用 [应用自检夹具](../doc/large-file-duplicates-plan.md#验收) 验证。ZIP 读取器通过 [CleanerZIP](../Sources/CleanerZIP/CleanerZIP.h) 绑定 macOS 的系统 libarchive，包构建无需下载 ZIP 依赖。

默认选择修改必须同时核对Skill/MCP：`.agents`默认保留、独立重复副本可预选、`.cache`无需包含关系、明确保留优先、不可选缓存不预选、待删缓存不能支撑其他删除、无模型/索引不阻断缓存预选。目录以AppModel注入home为边界；Skill/MCP本体、manifest及父目录软链接均须在发现/清单入口排除，不改Agent配置或迁移入口。覆盖只使用当前通过检查的清单对象；历史对象不参与新配对，真实对象恢复时用已有向量补齐缺失关系。定向检查见[软链接验证](../Tests/agent-symlink-exclusion/README.md)及Tests/agent-overlap-diagnosis。

根目录AGENTS.md已按用户要求删除，不由工作流自动生成或重新维护。协作偏好以用户当前明确指令为准，历史审计中的该文件记录仅说明当时修改。

卸载筛选栏验收须覆盖四项反复切换与窄窗口；只查看初始截图或检查fixedSize不足以证明布局稳定。Agent行验收检查左右栏顶部对齐、元数据紧随左栏描述、Top 3比例列对齐且无Combined Coverage；内部累计预选保持原有规则。

工具栏与侧栏继续由NavigationSplitView原生跟踪分隔符对齐；诊断证明几何分栏已正确，额外标题栏背景造成可见缺口，因此隐藏该背景并使用透明标题栏让全高度分栏背景连续；禁止硬编码宽度偏移。macOS27应实际检查边界，不能仅凭API存在宣称修复。

权限状态刷新覆盖首次提醒判定、扫描开始和设置页进入/返回。FDA沿用用户/系统专用TCC目录列举；明确拒绝与缺失/一般错误分类不变。首次扫描未确认FDA才进行一次现有只读预访问；不保留PermissionSetupView、preflightComplete/busy或重复配置按钮。App管理仍按真实卸载结果记录，界面使用固定说明；清理资格和系统保护不变。

应用漏扫排查应先在 All 范围按名称/Bundle ID/路径核对。Protected、Running、Uninstallable 为互斥分区：系统应用只进入 Protected，其余应用按运行状态分别进入 Running 或 Uninstallable；初始范围保持 Uninstallable。不可用静态写权限、Bundle ID 的 Apple 前缀或输入法类型推断永久保护。Running 中第三方应用允许勾选退出，系统应用不显示操作复选框；退出后移入 Uninstallable 才可选择卸载项目，重新启动立即移回 Running 并清除卸载选择。Uninstallable 不显示退出按钮。权限问题通过真实执行错误及既有恢复流程处理。变更须覆盖分区无重复/无遗漏、只读应用/父目录、第三方输入法、运行状态切换、Siri AI 等系统应用以及卸载路径与恢复路径的一致性。Agent 两种列表继续复用大文件的底部分隔线。

应用状态文案精简：使用原“系统保护”文案键统一短标签Protected/受保护；Running只在右侧状态说明显示，应用名旁不重复添加。修改文案时不得更改固定分段宽度、筛选语义或运行/系统应用的卸载保护。

Top3路径tooltip：完整路径从同一targetID去掉skill|或mcp|前缀，显示文本保持中间截断，原生help绑定在各target的VStack；父级整栏不得添加help覆盖逐项路径。Skill/MCP共享AgentContainmentLabel，不新增自定义悬浮窗口或状态。

Agent行底线和高亮必须在同一内容padding后绘制，ListRowBackground仅透明；不要混用系统整行背景和内层overlay，从而引入行内边距/高度差。

Agent双栏验收：Skill/MCP切换及长名称/路径时右栏起点保持一致，标题与各覆盖项名称/路径左对齐，比例保持固定数值列；无结果状态也使用相同360pt右栏。左栏minWidth=0允许收缩，覆盖栏优先保持宽度。不要恢复每行MCP服务器数量徽标。FDA Available来自只读探测，App管理不做试删或伪造Available。

全部默认清理必须复用 DefaultCleanupSelection 的可执行集合；系统与大文件默认项需仍在 selectedIDs，Agent 需同时属于自动预选 IDs。修改选中或自动预选时使缓存失效；分模块统计在全局父子/重复去重后计算，零值和手动维度不显示。三张安全卡直接放在标题下、扫描按钮行上方；不再展示原两行说明。回归覆盖 Agent 单独可执行、取消勾选、活动/保护、异步预选与扫描门禁；只读夹具不执行真实清理。

跨模块默认计划通过 DefaultCleanupSelection.buildPlan(using:) 将原始候选先交给 PlanBuilder；不得将已去重的展示候选直接当成计划输入，以免系统安装包别名或父目录遮蔽大文件保留副本证明。执行和回执使用最终 plan.selectedItems。

三张安全卡和下方操作行统一使用左 52pt、右 24pt 的外边距；左右边界分别对齐标题文字和废纸篓按钮右边缘，安全卡三列与操作行均用 12pt 间距，避免把边距分别加在首列与末列。

Scan 按钮可见高度为 56pt（约原来的两倍），使用专用 SwiftUI ButtonStyle 保留按压、禁用、焦点轮廓和原生 Button 无障碍语义，计时在按钮右侧，左右外边界保持一致。模型/项目页的顶部 NSButton 复选框显示本地化 Select All/全选，组内仍为无文字小复选框；顶部摘要至少 200pt，计数使用固有宽度，ViewThatFits 在窄窗口分行。Project Artifacts 的标题、侧栏和首页统一来自同一个翻译条目。

项目目录设置使用草稿和同一个持久化入口，三行视口不能裁掉保存范围；移除仅改配置。自检覆盖默认完整列表、去重、空列表、重开、实际写入失败保留旧配置、不触发首次扫描、只刷新项目、取消刷新后的旧范围门禁，以及保存时禁止新扫描/权限继续/模块续跑与清理。配置错误必须在项目页无结果时也可见。原生验收只编辑草稿后撤销，不改变用户真实配置，不执行清理；记录见 [设置验证](../Tests/project-scan-roots-settings/README.md)。

资源默认值须在 AppModel 模块结果边界应用，不能放在 View.onAppear 或每次报告变化时全选。回归覆盖两维度首次/渐进发布、受保护/空集合回退 All、旧 ID 替换、本模块刷新保留其它维度、搜索排序保留、用户取消后导航/无关发布/最终汇总不重选，并确认只有项目预选加入首页队列、模型无默认且手动选择不加入。使用既有导航自检与只读原生扫描，材料见 [验证记录](../Tests/resource-cleanable-defaults/README.md)。

Agent 默认空回退必须区分自动默认和用户主动筛选；Picker、列表和空态继续共用同一 agentItemsSelectionFilter。类型/平台/选择变化后缓存必须刷新，Skill/MCP 过滤循环内不得反复扫描全部列表来解析默认。回归包括延迟预选、自动 Selected/All 互换、手动空 Selected 和 All 保留、类型平台切换和既有性能门禁。大文件初始 All 已符合要求，手动空重复范围不自动切换。验证见 [本批记录](../Tests/agent-empty-default-scope/README.md)。

上一轮资源汇总和 DMG 归属见 [实施计划](../doc/cleanup-center-resource-sync-plan.md)。ProjectArtifactScanner 识别工程内独立及构建目录内的 DMG；Git 跟踪、路径/身份/活动检查继续用于执行复验。ProjectInstallerOwnership 从大文件展示清单和树中排除已归项目的 DMG，原始候选保留以便刷新与副本保留证明校验。项目/大文件渐进结果先后不影响最终归属。构建进程目录仅进入 projectActivePaths，具体文件仍进入 activePaths；项目目录保持活动保护，未打开 DMG 不因 cwd 被整目录保护。项目根待刷新时，首页排除旧项目默认项。验收与逐文件审计见 [本批记录](../Tests/cleanup-center-resource-sync/README.md)。

项目 DMG 接管大文件副本时保留 largeFileProof，并保护其保留文件及覆盖该文件的目录。项目范围变化按路径迁移已选/撤选状态，不重新勾选人工撤选；单项取消子 DMG 时同步取消包含它的目录，选中目录包含其可清理子项。分组和首页容量都按最终目录操作去重。

本轮更新见 [计划](../doc/project-installer-discovery-plan.md)。项目 DMG 发现与副本证明由 ProjectArtifactScanner 承担；大文件发布前依据同一项目根/manifest 规则排除其清单与容量树，避免临时默认数后续消失。正式 App 显式链接实际 SDK 与独立的 macOS 13 最低版本，记录 DTSDKName 并与 Mach-O 复核。删除手动标题栏背景干预，由原生 NavigationSplitView 和 unified 工具栏管理边界；不再混淆 SDK 与最低系统版本，不使用固定偏移。模型保留分类，但始终手选；证据见 [验证记录](../Tests/project-installer-discovery/README.md)。

当前布局更新：磁盘从清理中心移至 Tools 下方的侧栏底部，显示硬盘图标和“磁盘空间”标题、容量条及可用空间；继续共用 AppModel 的读取、错误与自动刷新状态，不复制数据源。侧栏和清理中心底栏共用 SidebarSurface 的不透明系统底色，跟随系统外观，避免桌面透色差异；其它维度底栏继续使用原 bar 背景。见[实施计划](../doc/dashboard-sidebar-footer-plan.md)和[逐文件验证](../Tests/dashboard-sidebar-footer/README.md)。


本轮项目选择策略见 [实施计划](../doc/project-selection-preferences-plan.md) 和 [逐文件验证记录](../Tests/project-selection-preferences/README.md)。设置切换即时更新既有结果和首页缓存，关闭仅撤销自动选择，不清空人工决定；扫描或执行期间禁用开关。Git 跟踪 DMG 使用同一手选快照边界，仍检查路径、权限、云盘、包、保护和活动；不加入自动副本保留证明。未知 Git 状态与其它保护继续执行复验。


关闭/退出共用 requestEmptyTrash 的工厂及执行器，关闭提醒额外显示“不再提醒”，手动清空及明确退出保持无 checkbox，不复制弹窗。抑制只改原偏好，失败也尊重选择；成功才确认清空量。Cancel 不清空并允许明确退出，同意清空后等任务/容量/错误提示结束再退出；willTerminate 后不得再次弹关闭提醒。红色关窗仍保留后台会话。现行证据见 [关闭提醒回归](../Tests/close-trash-reminder-choice/README.md) 和 [真实进程退出回归](../Tests/quit-without-emptying/README.md)。

0.4.30 移除扫描对清空的限制；确认框只在取得执行锁后显示，Empty Trash 始终可用。真实模型与模拟执行器的并发进度、两个入口及成功/失败验证见 [扫描中清空](../Tests/trash-during-scan/README.md)。

首次进入性能必须从空计划缓存测量列表、底栏和首屏行，另测图标；旧测试预热后再计时不能替代。只准备当前行、空选择汇总直接零，批量保护仍逐项检查实际路径；新报告、保护变更、进程启动/退出和 receipt 选择回归必须保持。见 [性能计划](../doc/application-first-entry-plan.md) 与 [逐文件验证](../Tests/application-first-entry/README.md)。
# 0.4.27 验证入口

- 导航状态：`.build/debug/CleanerApp --navigation-presentation-self-check`，六模块及旧报告/终态边界。
- Trash 执行门禁：`.build/debug/CleanerApp --trash-emptying-self-check`，只使用模拟执行器。
- 原生关闭：`zsh Tests/exact-trash-dialog/run-native-check.sh`，增加繁忙时重复 close、延迟成功记账、空清理回归；不接触真实废纸篓。
- 本轮日志、失败基线、逐文件说明：[Tests/module-progress-trash-reminder](../Tests/module-progress-trash-reminder/README.md)。
