# 0.3.28 代码整理与导航性能验收

本批次以 0.3.27 (101) 的工作区和应用包为基线，保留扫描范围、推荐规则、卸载归属判断、勾选语义、权限流程与可恢复清理方式。改动范围是文件职责拆分、重复展示计算的缓存，以及 Agent 扫描阶段提示。

## 文件职责

| 文件 | 职责 |
| --- | --- |
| `Sources/CleanerCore/ApplicationModels.swift` | 应用、清单、关联文件和卸载计划的数据类型 |
| `Sources/CleanerCore/BundleApplicationMetadataProvider.swift` | 读取应用包元数据和内嵌标识 |
| `Sources/CleanerCore/ApplicationInventory+SharedDeclarations.swift` | 有预算的共享容器声明补全 |
| `Sources/CleanerCore/ApplicationScanner.swift` | 发现应用与建立关联索引 |
| `Sources/CleanerCore/UninstallPlanner.swift` | 创建卸载计划和测量大小 |
| `Sources/CleanerCore/LargeFileScanner.swift` | 将磁盘扫描结果转为大文件候选 |
| `Sources/CleanerApp/CleanupActionBars.swift` | 清理中心及各栏目底部操作栏 |
| `Sources/CleanerApp/AgentEnvironmentProgressView.swift` | Agent 阶段进度提示 |
| `Sources/CleanerApp/NavigationPresentationFixture.swift` | 导航性能自检的只读数据夹具 |

上述拆分的原有声明与实现已和整理前快照逐段比较，没有更改内容，也没有扩大原有私有成员的访问范围。

## 导航计算

采样确认旧版在切页和绘制底部操作栏时反复执行以下工作：

- 遍历 Agent 资源、提取候选、筛选选中项，再统计筛选隐藏项。
- 重建默认清理集合并逐项校验保护路径。
- 每次勾选变化重新建立 Skill 与实体目录关联。

报告计算现在按其输入失效：新报告、已清理项和保护清单变化会清除候选/默认清理缓存；选择与筛选变化会清除选择/可见项缓存；模块是否就绪仍在读取时判断。删除执行前继续使用原有实时验证链路。

Skill 与实体目录关联在后台准备。选择变化复用关联，仅更新选中 ID；核心契约把更新后的完整结果与从头重建的结果比较，要求逐项相同。其它模块发布进度或报告时，不再无条件丢弃相同的 Agent 关联。

Agent 页会按阶段显示等待扫描、正在扫描、准备列表、分析覆盖关系和生成预选建议。扫描/准备阶段的空集合不再显示“没有已选中的 Skills”。

## 自动验证

- 整理前后 `swift test`：184 项，0 失败。
- 整理前后 `CoreContractChecks`：通过；新增选择关联等价检查。
- `--navigation-presentation-self-check`：2 万 Agent 资源、5000 清理项，20 次重复读取由 12.82 秒降至小于 1 ms；检查选择、清理、保护清单和扫描就绪状态的失效行为。
- 原有权限窗口、Agent 预选、并发扫描/清理、更新、清理/恢复自检继续保留；专项自检加入 `Scripts/verify-app.sh` 的交付验收。

## Computer Use 验收

整理前已在真实安装版 0.3.27 记录全部栏目、扫描结果、卸载展开/勾选/清空行为和切页耗时。实际删除和恢复由隔离夹具自动执行，真实文件界面只操作导航、筛选、展开和可逆勾选。

整理后的验收直接启动只读挂载的 DMG 内应用，而不是另一个开发可执行文件：

| 项目 | 当前实机证据 |
| --- | --- |
| 应用身份 | 设置页显示 `0.3.28 102` |
| 扫描前权限窗口 | 点击 `Scan with Current Access` 后窗口立即关闭，主界面进入等待扫描状态 |
| Agent 等待阶段 | 显示 `Waiting to scan Agent Environment…`，不显示 `No selected Skills` |
| Agent 实际扫描阶段 | 完全磁盘访问授权及重启后，显示 `Scanning Agent Environment for Skills and MCP configurations…` |
| 大文件操作 | 全部/重复范围切换、文件名搜索、安装包取消勾选及恢复均通过，4 个安装包默认选择保留 |
| 栏目可用性 | 等待权限时，卸载、大文件、恢复、设置和 Cleanup Center 均可导航 |
| 完整扫描 | 用户确认开启完全磁盘访问并完成触控 ID；权限生效、应用重启后，四个模块均完成，本次约 8 分 09 秒（旧版基线约 7 分 43 秒；文件树与 I/O 状态不同，未更改扫描范围） |
| 卸载 | 95 个应用；默认不勾选。CaptureThis 本体及两个关联项与整理前一致：3 项、约 13.1 MB；展开、组选择和清空通过，清空后删除按钮禁用 |
| 系统清理 | 推荐与保留分组正常；ChatGPT 日志仍在推荐组。应用组取消/恢复勾选后数量恢复一致 |
| Agent 结果 | 与旧版基线一致：3013 Skills、29084 个重复发现折叠、1065 个预选对象、14931 个关联目录单元；46 个 MCP 配置、44 个服务器定义 |
| Agent 控件 | Skills/MCP 切换、All/Selected、Claude Code/全部平台筛选、MCP 取消与恢复勾选通过；最终恢复全部平台、已选 Skills 和原选择总数 |
| 恢复与设置 | 恢复记录入口可用；设置显示 0.3.28 (102)、磁盘权限 Available、100 MB 阈值和安装包预选开启，符合原设置 |

### 页面切换实测

下表为原生 computer use 的点击至完整可访问界面返回耗时，包含自动化读取可访问树的开销；并非纯绘制帧耗时。

| 路径 | 整理前 | 整理后 |
| --- | --- | --- |
| 扫描后首次打开 Agent | 3562 ms | 1092 ms，点击响应 90 ms |
| 卸载 → Cleanup Center | 原返回中心测量约 1372–4181 ms | 三次 951 / 900 / 1343 ms；点击 73–74 ms |
| 大文件 → Cleanup Center | 原返回中心测量约 1372–4181 ms | 三次 1015 / 1436 / 1334 ms；点击 72–78 ms |
| Cleanup Center → Agent，重复打开 | 两次 2293 / 1851 ms | 三次 1482 / 1564 / 1519 ms；点击 77–89 ms |

旧版返回中心基线来自多种来源页的混合往返样本，未逐条保留来源，因此两个返回路径共用基线范围，不能据此比较两个来源页各自的提升比例。整理后未再观察到持续转圈或长时间主线程阻塞。

上述自动检查和实机流程均通过，未发现本批次引入的功能回归。未在真实文件上执行删除；删除、隔离、恢复、并发互斥、身份变化与错误处理由隔离夹具及打包自检验证。

## 交付

- DMG：`build/SuperCleaner-0.3.28-102.dmg`，301156420 字节。
- SHA-256：`c5247a70b2e015533e2dca5d60ea1ff2d7abe247792929db37e1058e68dabe40`。
- 已只读挂载验明版本 0.3.28 (102)、拖拽安装布局、应用深度签名与内置模型哈希。
- 当前机器使用 ad-hoc 本地签名，未公证；本批次未更改签名方案。
