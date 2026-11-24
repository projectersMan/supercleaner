# MangoDisk 与 SuperCleaner 源码对比及借鉴路线

调研日期：2026-11-24。本文回答产品取舍与实施顺序，本次不修改清理功能。

## 结论

MangoDisk 的优势集中在**跨平台的通用磁盘工具覆盖、空间可视化、细粒度筛选与批量操作，以及可复用的扫描基础设施**。SuperCleaner 的优势集中在**macOS 原生集成、Agent 工作区与能力关联分析、跨维度清理计划、执行前复验和可恢复执行**。建议保留 SuperCleaner 的 SwiftUI 与现有安全执行链，先补足“让用户理解空间、理解漏扫、理解保留依据”的产品层，再引入经过基准验证的扫描优化。

一个必须先澄清的事实：**MangoDisk 的发布说明不能完全代表其公开源码已经实现的能力**。本次确认的 `main` 和 `v2.1.1` 标签源码，大文件与重复文件的 GUI 调用仍进入永久删除接口；公开删除边界明确说明不提供通用回滚。发布说明提及的“默认回收站”“替换为链接”和“持久扫描记录差异”，应保留为官方宣称，不能据此认定公开实现已经具备这些功能。下面分别标明证据等级。[M03] [M04] [M05] [M06] [M07]

## 比较基线与证据边界

| 项目 | 本次基线 | 验证方式 |
|---|---|---|
| MangoDisk | `main`：`e4d30608faea9527369ee678e6d8ca9a9e1c3688`；工作区版本 2.1.1 | 官方 GitHub API、只读克隆、源码调用链、规则、测试和工作流审阅 |
| MangoDisk 正式标签 | `v2.1.1`：`d2a4fd6597524eb77b0687cfe1c9e6f533fae7c9` | 额外读取标签；与上述 main 仅有版本号、README 和配置等 10 个文件差异，业务源码相同 |
| SuperCleaner | 已推送并核对远程的 `6ef0200992a0d305badabec3ba12873963012f33`；版本 0.6.14（190） | 本地源码、现有测试与本次构建证据；源码以本地相对路径引用，便于 IDE 跳转 |

证据等级：**源码确认**指存在可追踪的实现；**发布宣称**指 README/Release 说明，但本次没有确认对应实现；**未实测**指未运行 MangoDisk GUI、发行二进制或其完整测试，因此不下性能、兼容性和实际误删率结论。SuperCleaner 最近完整运行的 430 项 Swift、18 项 Python 测试及本地签名/独立运行/DMG 校验通过，这些结果不能与未执行的 MangoDisk 测试作通过率比较。[M01] [M02] [M03]

临时源码位于 `Tests/temporary/research-mangodisk/MangoDisk/`。本文的 MangoDisk 源码链接均固定到上述 main 提交，避免后续更新改变本次结论。

## 核心能力对照

| 维度 | MangoDisk：公开源码确认范围 | SuperCleaner：本地确认范围 | 取舍 |
|---|---|---|---|
| 产品范围 | macOS、Windows、Linux；磁盘分析、深度清理、独立大文件/重复文件、卸载、启动项、隐私、系统设置/维护、监控和清理 CLI | macOS 13+；系统、卸载、大文件、Agent、本地模型、项目六维度；历史与恢复 | MangoDisk 广度更大；SuperCleaner 可集中投入 macOS 与 AI 开发者场景。[M01] [M08] [S01] |
| 空间分析 | 可切换矩形图/旭日图、深度控制、图表/列表联动、目录下钻、覆盖详情、层级导出 | 大文件目录树、目录分组、重复副本列表；侧栏实际磁盘容量 | MangoDisk 对“空间去哪了”的解释更直观；SuperCleaner 当前主要服务清理候选审阅。[M09] [M10] [S02] |
| 大文件发现 | 原生平台候选源、索引/遍历回退、会话与索引复用 | 优先 Spotlight `MDQuery`，不可用时目录遍历；项目 DMG 先完成归属排除 | 两边都已有加速路径，不能把本地项目描述为只会全盘逐文件扫描。[M11] [S03] [S04] |
| 重复判定 | 大小分组、物理文件身份去重、分段采样、BLAKE3 全量哈希、并行流水线、内存哈希缓存；也支持目录重复聚合 | 内容副本、ZIP 与完整解压目录、安装包推荐；保留件证明进入执行校验 | MangoDisk 的查重工具形态和用户保留策略更丰富；SuperCleaner 的归属/保留约束与总计划结合更深。[M12] [M13] [S05] |
| 扫描完整性 | 权限、读取错误、排除项、链接/挂载边界和未知原因分开；大小有 complete/partial/unavailable | 具备 CoverageSummary、ScanLimitation、模块受限状态及查重预算提示 | 借鉴的是统一、可解释的呈现，不是从零增加覆盖数据。[M10] [M14] [S02] [S03] |
| 清理安全与恢复 | 原生会话校验、保护路径、无跟随链接、物理身份、部分失败及取消；公开通用文件删除链为原地永久删除 | 不可变计划、实时资格/身份/归属复验、隔离或 Trash、执行 journal、恢复与恢复 journal | 对需要“删错能找回”的产品目标，本地执行闭环更合适；MangoDisk 同样有前置校验，不能仅凭出现 shell 删除命令判定其没有安全边界。[M06] [M15] [S06] [S07] |
| 应用卸载 | macOS 与 Windows，组件清单、用户数据风险分级、计划指纹、卸载前重新检查、Windows 厂商卸载器 | macOS Bundle ID、组件声明、entitlement、收据与共享归属，执行前重读声明，Helper 受限操作 | 广度上 MangoDisk 更强；在本机 macOS 归属复验及可恢复性上，本地实现更深入。[M16] [M17] [S08] [S09] |
| AI 相关清理 | 规则覆盖 AI 工具缓存及多种模型，包括 ModelScope、Jan、Coqui、ComfyUI；解析 `OLLAMA_MODELS`、`HF_HOME` 等环境配置及 ComfyUI 模型路径；Ollama provider 使用 whole-root 粒度 | 七类本地模型，当前存储根主要固定拼接到 home；Ollama 按 manifest/tag 展示与共享 blob 核验；Agent Skills/MCP/会话/工作树及相关性分析 | MangoDisk 的发现广度与自定义存储支持更完整；SuperCleaner 的模型引用关系与 Agent 能力治理更有区分度。[M18] [M33] [S10] [S11] [S12] |
| AI 使用方式 | 用户按条目请求远程 AI 解读，支持官方服务/自定义服务；解释不改变选择和原生执行权限 | Agent embedding 在本机独立进程推理；模型有显式下载接口 | MangoDisk 强于自然语言解释；SuperCleaner 的本地语义处理更利于减少数据外发。两者用途不同，不宜把“都有 AI”当作同一种能力。[M19] [S13] |
| 系统工具 | 启动项、系统维护、隐私数据和资源监控具备实际模块；Windows 另有右键菜单 | 当前重心是扫描、清理、卸载、恢复，不承担完整系统工具箱 | 新增这些模块会显著扩大权限与测试矩阵，不能只按功能数量评价。[M20] [S01] |
| 工程与发布 | Vue/TypeScript/Tauri + Rust Core/Platform/Privileged/CLI 分层；跨平台 PR 检查、规则检查、合成基准、实际 Release 附件 | Swift/Core/App/Helper/独立推理；本地契约/XCTest/签名/独立运行/DMG 一致性验证；根目录未查到 `.github` 工作流 | MangoDisk 的公开协作与平台矩阵更完整；本地具有较强的交付物验证，但自动发布证据和可复现性能基线仍值得补强。[M08] [M21] [M22] [M23] [S14] |

## 四个容易误判的关键点

### 1. 发布文案和公开实现存在边界差异

官方 `v2.1.0` 说明提到大文件/重复文件默认回收站，`v2.1.1` 说明提到重复文件替换链接和持久扫描记录比较。实际公开链路为：

```text
large-files-store.ts
  → PermanentDeleteService.deleteFiles
  → invoke("delete_files_permanently")
  → LargeFileService::delete_files_permanently
  → filesystem::permanent_delete

duplicate-files-store.ts
  → DuplicateFileService.deletePermanently
  → invoke("delete_duplicate_files_permanently")
  → DuplicateFileService::delete_files_permanently
```

右键菜单也直接使用 `common.deletePermanently`。`filesystem/README.md` 明确写明不创建通用备份、不进行一般回滚，且承认部分元数据检查之后的并发变更风险。标签 `v2.1.1` 中该服务调用相同。公开 `analysis` 的 snapshot 主要是当前扫描的会话/内存索引，不能等同跨启动持久扫描历史。[M03] [M04] [M05] [M06] [M07] [M24]

这不证明发行二进制一定缺少这些功能，也不构成对其发布动机的判断；本次没有运行发行二进制。可得出的结论是：**以公开工程为移植依据时，不能直接拿发布文案当实现规格。**

### 2. 两边的“安全”策略侧重点不同

MangoDisk 并非只拿前端路径直接执行删除：它会约束 scan ID、扫描成员身份、保护目录、链接、目标物理身份与组件快照；macOS 受权卸载只针对受支持的应用根目录，参数经独立传递和 shell quoting，暂存后再次检查物理身份，并对异常恢复状态给出类型化结果。[M15] [M16] [M17]

但这些检查与“能够恢复用户内容”是不同能力。其大文件删除后的 `HistoryService::append` 失败仅记警告；SuperCleaner 的协调器在实际执行前持久化 journal，之后再收敛回执与恢复。这使本地设计在中断后的可追溯和恢复闭环上更完整。普通 `FileManager.moveItem` 仍不是整个文件系统事务，不能宣称本地所有竞态都被原子消除。[M25] [S06] [S07] [S15]

此外，MangoDisk 目录重复删除采用扫描时内容证明及目录元数据检查，文档明确不在执行时重哈希每个后代。SuperCleaner 应继续保留自己的执行前保留件、内容变化和共享引用复验，而不是为追求查重速度删掉这些约束。[M06] [S05] [S06]

### 3. 性能值得借鉴，但不能先宣称谁更快

MangoDisk 的具体可借鉴点包括 Darwin `getattrlistbulk` 批量读取、只请求当前任务需要的属性、受限并发、目录导航索引、根目录 LRU、generation/mutation revision 防止迟到发布、FSEvents 验证缓存和脏子树更新。哈希缓存只存性能结果，根/参数/排除规则不匹配或文件系统变更历史不可信时回到重新扫描。[M11] [M12] [M13] [M24] [M26]

SuperCleaner 已有六模块 TaskGroup 并发、Spotlight、大文件结果缓存与 Agent 增量能力索引。其文件系统目录枚举主要使用 `FileManager.contentsOfDirectory`；这是适合做同数据集基准后再替换的局部接缝。不要同时启动第二套独立扫描器和缓存体系，造成前端容量、候选归属和执行计划各自不一致。[S03] [S04] [S12] [S15]

尤其需要区分遍历和内容核验：正式运行时多处关闭条目/深度预算，不能从构造器默认值推导“扫描最多五万条”；但大文件重复/ZIP 内容核验默认仍分阶段限制 64 GiB、50,000 条、20 秒，命中后仅推荐已核验项并明确提示。项目 DMG 的相同分析则显式关闭该工作预算。这个限制可能影响用户找到全部重复项的预期，应在比较结果里显示清楚。[S03] [S05] [S16]

本次未做相同硬件、相同权限、相同数据、冷暖缓存的双项目测量，因此不提供“Rust 比 Swift 快几倍”或固定耗时排名。

### 4. 模型体积、隐私与平台门槛存在实际取舍

本地 embedding 模型资源为 309,855,456 字节；本次 SuperCleaner DMG 为 299,206,446 字节。MangoDisk 官方 `v2.1.1` macOS DMG 附件为 35,778,053 字节，前者约 8.36 倍。两者架构、压缩、签名和功能资源不同，不能把体积差异全部归因语言或 UI 框架；包内模型是本地体积的重要来源。[M03] [S13] [S17]

SuperCleaner 主程序支持 macOS 13，embedding 推理要求 arm64 且 macOS 14+，模型下载接口会联网。MangoDisk 可选 AI 会把允许范围内的条目名称、路径或软件身份元数据发往所选服务；配置中的 API key 保存在应用数据目录的 JSON，Unix 临时文件使用 0600，并非系统钥匙串。它对日志和模型输出有边界约束，但这仍是用户需要理解的隐私取舍。[M19] [S13]

双方仓库都带 GPLv3 许可证，MangoDisk manifests 更明确声明 `GPL-3.0-only`。不能把它描述为可直接无条件复制的 MIT 项目，也不能把本地有付费/试用逻辑等同于源码采用专有许可证。本文建议优先借鉴需求、行为和验证方法；若移植具体代码或规则，应另外核对对应文件的来源、许可和告知义务。本地历史、恢复、移除 Helper 和导出回执属于始终开放的安全权利。[M02] [S18] [S19]

## 可以直接借鉴的用户操作

以下步骤是建议的 SuperCleaner 目标行为；其中已有能力应复用，不重复开发。

| 场景 | MangoDisk 可验证操作 | 迁移到 SuperCleaner 的具体方式 |
|---|---|---|
| 找出空间占用来源 | 选磁盘/目录 → 扫描 → 矩形图/旭日图切换 → 调深度 → 图表/列表 hover 联动 → 点击目录下钻 → 右键打开/定位 | 在现有大文件树旁增加“空间分布”只读视图，复用同一候选和测量快照；先定位，再经现有清理计划执行。图表不能直接授权清理任意未知目录。[M09] [M27] [S02] |
| 处理“结果明显少了” | 点击覆盖提示 → 看权限/读错/排除/链接等分类 → 修改范围或补授权 → 明确重扫 | 将现有 CoverageSummary/ScanLimitation 汇总成详情；区分“扫描到零个”和“不可读取”，把查重预算与权限问题分开。不要为了展示更多数字绕过系统权限。[M10] [M14] [S03] |
| 决定留下哪份重复文件 | 选择保留最短路径/最短名/最新/最旧 → 智能选择 → 查看保留件 → 单组取消/重新选择 | 在现有重复组里增加保留策略入口；保护目录可作为仅保留来源。不能只改 `selectedIDs`：换保留件必须重建并绑定 `LargeFileCleanupProof`，保证新保留件不在待删除集合中，移动前继续复核内容、身份与引用。[M13] [M28] [S05] [S06] |
| 保存空间证据 | 当前目录 → 导出 → 选 JSON/Markdown、层级、条目数、是否全路径 → 原生保存窗口 | 从现有已发布快照导出，明确扫描时间、逻辑/分配字节口径、遗漏和折叠原因；导出不重新扫描、不把报告当删除授权。全路径开关默认强调个人信息暴露。[M29] [M30] |
| 扫描时继续使用旧结果 | 重扫期间保留之前的结果视图，同时显示新的进度；取消后仍能检查旧结果 | 区分“浏览旧快照”和“执行当前计划”；只读允许，旧 generation 的删除必须禁用或重新复验，防止迟到回调恢复过期选择。[M31] [S03] |
| 处理失败项 | 操作后显示失败原因、保留路径/部分结果 → 复制诊断 → 在文件管理器定位 | 复用本地删除结果与历史 UI，补齐按原因筛选和一键复制脱敏摘要；只重试失败项，且重新建立执行资格。[M32] [S06] [S20] |
| 了解冷门工具缓存 | 查看条目详情/AI 解读 → 理解用途及影响 → 用户自行决定 | 先让本地规则的来源、可重建依据、保留理由易读可见；远程 AI 解释作为独立可选能力，不让模型改变保护状态、选择或执行许可。[M19] [S12] |

## 建议优先级、成本与风险

分数表示对 **SuperCleaner 当前 macOS/AI 清理目标** 的建议价值，不是实测性能分。95 以上为最优先，85–94 为值得安排；低于 85 保留为方向选择。本次仅给研究与路线，不因得分而自动实施新功能。

| 建议 | 局部/全局 | 分数 | 预计工作量 | 风险/约束 | 建议优先级 |
|---|---|---:|---|---|---|
| 把已有覆盖数据做成可解释详情，区分权限/排除/索引/查重预算 | 局部 | 98 | 小–中 | 不把受限当空；计数不重复累加父子项 | P0 |
| 重复组保留策略、仅保留目录、组级选择反馈 | 局部 | 96 | 中 | 执行保留证明继续由 Core 校验 | P0 |
| 从现有快照导出 JSON/Markdown，记录时间/测量口径/遗漏 | 局部 | 94 | 中 | 路径隐私、导出体积、整数精度、原子写入 | P0 |
| 统一扫描证据对象，列表/图表/导出共用 generation、范围、权限、口径和复验边界 | 全局 | 97 | 中–大 | 复用 SystemScanReport，避免第二份事实与第二套执行器 | P0/P1 |
| 合成基准数据集与冷暖缓存基线，加入重复证明及结果集合一致性检查 | 全局 | 96 | 中 | 先保证扫描集合/容量口径一致，再比较速度 | P0/P1 |
| 空间矩形图、图表/表格联动和目录下钻，先提供一个图表模式 | 局部 | 93 | 中–大 | 小文件聚合、部分覆盖、硬链接及稀疏文件计量 | P1 |
| 对实际热点引入 getattrlistbulk，按用途裁剪属性，并保留可靠回退 | 全局 | 90 | 中–大 | 原生结构解析、文件身份/链接/挂载语义不能变化 | P1 |
| FSEvents 驱动缓存失效/子树刷新，历史丢失即重建 | 全局 | 89 | 大 | 改名、权限变化、挂载变化、事件丢失；缓存不是执行授权 | P1/P2 |
| 模型发现范围扩展与自定义根：环境配置、ModelScope/ComfyUI/Jan 等，先只读展示 | 局部 | 95 | 中 | 环境变量只提供发现线索；执行前仍需 PathPolicy、来源证据、显式范围授权及共享引用复验 | P0/P1 |
| 失败原因聚合、定位和脱敏诊断复制；重扫期间保留旧结果只读 | 局部 | 91 | 中 | 不复用旧执行许可；不能在日志中泄露私有路径/令牌 | P1 |
| 提供“基础包/含本地模型包”两种交付方式，复用已有模型下载/校验接口 | 全局 | 87 | 中 | 保留离线包；基础包不静默联网；两种包执行/恢复行为一致 | P2 |
| 只读扫描历史与目录变化比较 | 全局 | 87 | 大 | 自己实现并验证；不能照搬尚未确认的 Mango 公开能力；历史测量不授权删除 | P2 |
| 增加统一 CI、基准/契约、包内资源及正式发布校验 | 全局 | 94 | 中 | 本机签名阳性不等于公证、真实升级和干净机验收 | P0/P1 |
| 远程 AI 自然语言解读 | 局部 | 80 | 中–大 | 数据外发、凭证、调用费用、幻觉；先完善确定性解释 | 待用户取舍 |
| 启动项管理 | 全局 | 78 | 大 | 需要单独可恢复变更模型和权限边界，扩展当前产品范围 | 待用户取舍 |
| 重复副本替换为硬链接/软链接 | 局部 | 70 | 大 | 内容相同不证明路径可互换；共享写入、跨卷、软件引用、回滚语义复杂 | 暂缓 |
| 系统设置优化、隐私数据库清理、内存自动释放、常驻硬件监控 | 全局 | 60 | 很大 | 持续采样成本、不可逆状态、用户数据与系统权限显著扩大 | 暂缓 |
| 为了跨平台将现有 SwiftUI/Core 重写为 Tauri/Rust | 全局 | 52 | 很大 | 当前没有明确跨平台需求，迁移损失会超过可验证收益 | 暂缓 |

## 推荐实施路线与验收标准

### 第一阶段：提高决策质量，保持现有执行链

1. 增加扫描覆盖详情：每个模块显示范围、数据源、时间、完整性和遗漏原因，查重核验预算单列。
2. 增加重复组保留策略和明确的保留件说明；复用现有选择快照与 Core 保留证明。
3. 增加快照导出与失败诊断复制；先以 JSON/Markdown 和一个稳定 schema 完成，不同时新增导入执行功能。
4. 将合成数据的扫描集合、去重、保护、恢复和计量一致性加入持续检查。

验收：同一筛选下列表/选中/底栏/计划的集合一致；权限受限与空目录可区分；切换保留策略不执行 IO；不能选光同组副本；导出过程不扫描文件、不泄露默认未勾选的完整路径；发生失败可以定位到具体步骤并保持可恢复性。

### 第二阶段：空间解释与有证据的性能优化

1. 统一只读扫描证据接口，增加单一矩形图模式及图表/目录列表联动；需要时再增加旭日图。
2. 用固定种子合成目录、海量小文件、重复内容、采样碰撞、权限拒绝、硬链接、稀疏文件、符号链接和跨卷边界数据集测量。
3. 先定位耗时占比，再试验 Darwin 批量枚举与哈希流水线；FSEvents 缓存最后接入。

验收：优化前后候选集合、归属、保护理由、逻辑/分配字节口径一致；冷/暖扫描和 UI 首批结果时间分别报告；事件丢失和缓存不可信时重扫；不能用截断候选、少做内容校验来获取漂亮耗时。

### 第三阶段：扩展 AI 场景与交付方式

模型发现可先行做只读增量：从 `LocalAIModelScanner` 的固定根扩展为“内置根、环境发现根、用户显式保存根”，展示来源、容量和覆盖情况。进入可执行范围前统一现有 `PathPolicy`、归属证据和显式授权；不能仅凭 `OLLAMA_MODELS` 或文件夹名把任意目录放开删除。继续保留本地 Ollama manifest/tag 与共享 blob 粒度，不移植 MangoDisk 的 whole-root 删除方式。

在此基础上再评估两种模型交付包与只读历史空间变化。启动项、系统维护、隐私清理、远程解释和跨平台属于产品范围决策，应分别立项，避免一次比较报告变成系统工具箱重写。

## 研究限制与反思

- 本次已追踪公开源码和标签，没有运行 MangoDisk GUI，也没有下载/运行其发行二进制；不能证明发布包签名、公证、功能与公开源码的一致性。
- 未在相同数据集实测两项目，包体大小可直接读取，但运行速度、内存和误删概率不能据架构或语言推断。
- 未查到某入口只意味着本次公开代码范围未证实，不等于外部服务、私有发布流程或其他分支永远不具备该能力。
- MangoDisk 的模块广度和原生 API 值得学习，但不宜照搬其通用永久删除边界；SuperCleaner 的本地模型与恢复链有成本，也应让用户看到体积、权限、完整性和恢复范围。
- 不建议为每个借鉴点新增缓存、执行器或平行扫描事实。最有价值的全局改进是让现有证据在界面中变得清楚，并用统一数据和基准验证其正确性。

## 一手证据索引

MangoDisk：

- [M01：README 与平台/产品范围][M01]
- [M02：Cargo workspace、GPL-3.0-only 与模块边界][M02]
- [M03：官方 v2.1.1 Release、附件大小与发布宣称][M03]
- [M04：官方 v2.1.0 Release，默认回收站宣称][M04]
- [M05：大文件 GUI 服务的永久删除调用][M05]
- [M06：公开永久删除安全边界及已接受风险][M06]
- [M07：重复文件 GUI 服务的永久删除调用][M07]
- [M08：前后端依赖及工程检查入口][M08]
- [M09：图表模式、深度控制、视图联动][M09]
- [M10：覆盖详情 UI][M10]
- [M11：Darwin 批量属性枚举][M11]
- [M12：重复扫描与分段/全量哈希流水线][M12]
- [M13：重复组选择与保留策略][M13]
- [M14：覆盖分类、权限及配置指纹][M14]
- [M15：原地永久删除的实际检查][M15]
- [M16：卸载计划完整性][M16]
- [M17：macOS 受权卸载的根目录及物理身份约束][M17]
- [M18：模型 provider 与 Ollama whole-root 粒度][M18]
- [M19：可选远程 AI、上下文白名单、凭证和执行边界][M19]
- [M20：系统维护内置目录][M20]
- [M21：跨平台 CI][M21]
- [M22：可复现合成基准数据][M22]
- [M23：清理规则来源、schema 与专用 cleaner 边界][M23]
- [M24：分析索引缓存及 publication/mutation 约束][M24]
- [M25：大文件执行后历史写入失败的处理][M25]
- [M26：FSEvents 变更与事件失效处理][M26]
- [M27：图表右键操作边界][M27]
- [M28：保留策略的类型定义][M28]
- [M29：导出协议、范围、计量与原子写入边界][M29]
- [M30：导出实现][M30]
- [M31：重扫保留结果的 store 行为][M31]
- [M32：失败项分组与复制诊断 UI][M32]
- [M33：ComfyUI 配置及模型根发现][M33]

SuperCleaner：

- [S01：项目模块与依赖][S01]
- [S02：大文件目录与筛选 UI][S02]
- [S03：模块并发、Spotlight 回退与查重受限状态][S03]
- [S04：Spotlight 元数据索引与身份检查][S04]
- [S05：内容查重、ZIP 与预算][S05]
- [S06：执行前资格与保留件复验][S06]
- [S07：持久 journal、回执、执行与恢复协调][S07]
- [S08：应用执行前完整组件声明复验][S08]
- [S09：应用声明及关联扫描][S09]
- [S10：本地模型发现][S10]
- [S11：Ollama 引用与共享存储][S11]
- [S12：Agent 资产与能力扫描][S12]
- [S13：本地 embedding、平台门槛及模型下载][S13]
- [S14：构建/签名/验证入口][S14]
- [S15：目录 IO、身份及普通移动实现][S15]
- [S16：项目 artifact 和 DMG 归属][S16]
- [S17：本次 DMG 重建验证记录][S17]
- [S18：GPLv3 许可证][S18]
- [S19：历史/恢复等安全权利][S19]
- [S20：历史与恢复 UI][S20]

[M01]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/README.zh-CN.md
[M02]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/Cargo.toml
[M03]: https://github.com/harry0703/MangoDisk/releases/tag/v2.1.1
[M04]: https://github.com/harry0703/MangoDisk/releases/tag/v2.1.0
[M05]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/lib/services/filesystem/permanent-delete-service.ts
[M06]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/filesystem/README.md
[M07]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/lib/services/storage/duplicate-file-service.ts
[M08]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/package.json
[M09]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/pages/analysis/components/md-analysis-visual-pane.vue
[M10]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/pages/analysis/components/md-analysis-coverage.vue
[M11]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-platform/src/macos/bulk_directory.rs
[M12]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/duplicates/service.rs
[M13]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/lib/utils/storage/duplicate-file-selection.ts
[M14]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/analysis/coverage.rs
[M15]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/filesystem/permanent_delete.rs
[M16]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/applications/uninstall/plan.rs
[M17]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-platform/src/macos/privileged_uninstall.rs
[M18]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/cleanup/cleaners/ai_model_storage.rs
[M19]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/ai/README.md
[M20]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/system_maintenance/catalog.rs
[M21]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/.github/workflows/cross-platform-check.yml
[M22]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/reporting/benchmark/dataset.rs
[M23]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/rules/README.md
[M24]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/index/cache.rs
[M25]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/large_files/service.rs
[M26]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-platform/src/macos/change_tracking.rs
[M27]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/components/custom/md-file-entry-context-menu.vue
[M28]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/lib/models/storage/duplicate-file.ts
[M29]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/analysis/README.md
[M30]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/storage/analysis/export.rs
[M31]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/stores/duplicate-files-store.ts
[M32]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src/components/custom/md-file-delete-failures.vue
[M33]: https://github.com/harry0703/MangoDisk/blob/e4d30608faea9527369ee678e6d8ca9a9e1c3688/src-tauri/crates/mangodisk-core/src/cleanup/cleaners/ai_model_storage/comfyui/config.rs
[S01]: ../../Package.swift
[S02]: ../../Sources/CleanerApp/DiskSpaceView.swift
[S03]: ../../Sources/CleanerCore/SystemScanCoordinator.swift
[S04]: ../../Sources/CleanerCore/LargeFileMetadataIndex.swift
[S05]: ../../Sources/CleanerCore/LargeFileContentAnalyzer.swift
[S06]: ../../Sources/CleanerCore/Execution.swift
[S07]: ../../Sources/CleanerCore/CleanupExecutionCoordinator.swift
[S08]: ../../Sources/CleanerCore/ApplicationExecutionValidator.swift
[S09]: ../../Sources/CleanerCore/ApplicationScanner.swift
[S10]: ../../Sources/CleanerCore/LocalAIModelScanner.swift
[S11]: ../../Sources/CleanerCore/OllamaModelStorage.swift
[S12]: ../../Sources/CleanerCore/AgentScanners.swift
[S13]: ../../Sources/AgentOverlapAI/AgentEmbeddingModelManager.swift
[S14]: ../../Scripts/build-app.sh
[S15]: ../../Sources/CleanerCore/FileSystem.swift
[S16]: ../../Sources/CleanerCore/ProjectArtifacts.swift
[S17]: ../history.md
[S18]: ../../LICENSE
[S19]: ../../Sources/CleanerCore/LicenseStore.swift
[S20]: ../../Sources/CleanerApp/HistoryView.swift
