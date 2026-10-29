# XApp 卸载扫描覆盖与移植边界

本批次将 XApp 当前版本发现卸载关联项的方法移植到本项目：补齐目录发现，复用目录表进行扫描、运行时线索归一化和执行前核对。**目录已纳入扫描不等于其中所有内容都可删除**；卸载候选仍需逐项确认归属、共享/引用状态及恢复能力。

## 证据范围

- 分析日期：2026-10-29；方式：REA + Hopper 的 arm64 静态分析，未执行 XApp 或被卸载应用。
- 目标：`/Applications/XApp.app/Contents/MacOS/XApp`。
- 二进制 SHA256：`6ad8a44d8ccd26dbe53e9d4701117ae8f8b9d42cdb04921d3bf886c433c0aa19`。
- 已跟踪总入口 `0x1000798c8` 的 11 类直接扫描调用；该入口 Evidence：`ev_5cffad6bcebdeab7f1298465a7e24da2ce868af0af0067bd9403aa472b7d18f2`。
- 保留目录：[/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit)，含完整函数 Evidence JSON、独立快照、目录清单、资源解码和 SHA256 清单；不依赖 `/tmp` 临时文件。
- 入口清单：[root-inventory.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/root-inventory.json)；证据索引：[evidence-index.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/evidence-index.json)；每个保留文件的校验值：[retained-file-manifest.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/retained-file-manifest.json)。

本表的“覆盖”仅指该二进制、该卸载扫描调用链和已检查打包配置；不是对 XApp 其他版本或全部运行时功能的穷尽声明。

## 11 类入口与项目实现

| 编号 | XApp 类别 | 函数 | 本项目对应 |
|---|---|---|---|
| E1 | 应用本体 | `0x100073bcc` | `ApplicationScanner.swift` 的应用本体计划项 |
| E2 | 沙盒容器 | `0x100073ccc` | `ApplicationAssociationPathRegistry.swift` 的 `.container` / exactIdentifier |
| E3 | 支持目录和实用工具 | `0x100075b8c` | 同表 `.applicationSupport`；Utilities 为 referenceOnly |
| E4 | 缓存 | `0x1000762d4` | 同表 `.cache`；厂商下一层候选发现 |
| E5 | 保存状态 | `0x100076ce8` | 同表 `.savedState` |
| E6 | 偏好设置 | `0x100076f5c` | 同表 `.preference`；兼容线索见后文 |
| E7 | 崩溃/诊断记录 | `0x10007759c` | 同表 `diagnosticRoots` + `ApplicationDiagnosticScanner.swift` 的单文件核对 |
| E8 | Web 数据、脚本和安装记录 | `0x100077a80` | 同表 `.webData` / `.applicationScripts` / `.installationReceipt` |
| E9 | 日志 | `0x100077dc8` | 同表 `.log`；诊断目录独立核对 |
| E10 | 全局服务 | `0x100078af4` | 同表 `.launchAgent` / `.launchDaemon`，只读关联 |
| E11 | 用户服务 | `0x100078cb4` | 同表 `.launchAgent` / `.launchDaemon`，只读关联 |

所有通用关联根由 `ApplicationAssociationPathRegistry.roots` 提供；`ApplicationOwnershipGraphBuilder` 消费该目录表建立资源所有者及引用图。扫描展示和 `ApplicationExecutionValidator` 的执行前归属复核复用这套图，避免界面能发现、执行却使用旧目录表的分歧。运行时观察仅提供相关线索，不单独授权删除。

## 24 个固定扫描根（去重）

`~` 在本项目解析为当前真实用户 home。XApp 的 home 辅助函数 `0x10005e5d4` 会重建 `/Users/<用户名>`；本项目没有复制这一硬编码。下表没有把应用本体路径算作固定目录，也没有因崩溃和日志两类都使用 DiagnosticReports 而重复计数。

“可手选”表示**满足逐项归属、无其他所有者/引用、文件类型等核对后**允许用户选择；不是默认勾选或保证每个匹配项都可删。“只读关联”仍可展示被发现的具体项目及保护原因，不加入可删除数量。

| # | 扫描根 | 本项目类型 | 删除边界 | XApp 入口 |
|---|---|---|---|---|
| 1 | `~/Library/Containers` | `container` | 可手选；用户数据 | E2 |
| 2 | `/Library/Application Support` | `applicationSupport` | 全局只读，用户目录可手选；用户数据 | E3 |
| 3 | `~/Library/Application Support` | `applicationSupport` | 全局只读，用户目录可手选；用户数据 | E3 |
| 4 | `/Applications/Utilities` | `plugin` | 只读关联；不自动卸载其他工具 | E3 |
| 5 | `/Library/Caches` | `cache` | 全局只读，用户目录可手选 | E4 |
| 6 | `~/Library/Caches` | `cache` | 全局只读，用户目录可手选 | E4 |
| 7 | `~/Library/Saved Application State` | `savedState` | 可手选 | E5 |
| 8 | `/Library/Preferences` | `preference` | 全局只读，用户目录可手选；别名线索另保护 | E6 |
| 9 | `~/Library/Preferences` | `preference` | 全局只读，用户目录可手选；别名线索另保护 | E6 |
| 10 | `/Library/Application Support/CrashReporter` | `diagnosticReport` | 单文件核对；全局只读，用户目录可手选 | E7 |
| 11 | `~/Library/Application Support/CrashReporter` | `diagnosticReport` | 单文件核对；全局只读，用户目录可手选 | E7 |
| 12 | `/Library/Logs/DiagnosticReports` | `diagnosticReport` | 单文件核对；全局只读，用户目录可手选 | E7, E9 |
| 13 | `~/Library/Logs/DiagnosticReports` | `diagnosticReport` | 单文件核对；全局只读，用户目录可手选 | E7, E9 |
| 14 | `~/Library/HTTPStorages` | `webData` | 可手选；用户数据 | E8 |
| 15 | `~/Library/Application Scripts` | `applicationScripts` | 可手选；精确 ID；用户数据 | E8 |
| 16 | `~/Library/WebKit` | `webData` | 可手选；用户数据 | E8 |
| 17 | `/private/var/db/receipts` | `installationReceipt` | 只读关联；安装来源记录 | E8 |
| 18 | `/Library/Logs` | `log` | 全局只读，用户目录可手选 | E9 |
| 19 | `~/Library/Logs` | `log` | 全局只读，用户目录可手选 | E9 |
| 20 | `/Library/LaunchAgents` | `launchAgent / launchDaemon` | 只读关联；需停止并注销服务 | E10 |
| 21 | `/Library/LaunchDaemons` | `launchAgent / launchDaemon` | 只读关联；需停止并注销服务 | E10 |
| 22 | `/Library/StartupItems` | `launchAgent / launchDaemon` | 只读关联；需停止并注销服务 | E10 |
| 23 | `~/Library/LaunchAgents` | `launchAgent / launchDaemon` | 只读关联；需停止并注销服务 | E11 |
| 24 | `~/Library/LaunchDaemons` | `launchAgent / launchDaemon` | 只读关联；需停止并注销服务 | E11 |

全局 `/Library`、`/private/var/db/receipts` 和 `/Applications/Utilities` 的关联内容统一标记 `referenceOnly`。不能把“扫描覆盖齐全”表述为“全局组件已实现自动卸载”；当前批次没有实现服务注销、插件卸载或安装包收据清理。应用本体是用户明确选择的 `.app`，有独立的运行状态、系统保护和文件身份复核。

## 匹配方法、特殊规则与移植处理

### 厂商下一层

XApp 通用函数 `0x100074a20` 枚举目录直接子项，以应用名/Bundle ID 的转义正则匹配；`0x100062ec0` 构造包含 `(?:\.[\w\d]+)*` 的扩展匹配。`0x10007464c` 推导厂商目录或使用别名，再对下一层重复匹配；`0x1000743a0` 包含特定厂商/产品的路径例外。

本项目对支持目录、缓存、日志和 Web 数据目录限定多看厂商下一层，厂商来自 Bundle ID 的第二段或 Google、Microsoft、JetBrains、Adobe、Apple、Logitech、Objective Development、Better365 等已知名称。厂商父目录从候选中移除；不跟随符号链接到目录外。产品目录仍按独立所有者图核对，名称线索不足时保持保护，不按“只有一个产品当前安装”推断整个厂商目录可删。运行时观察同样不把厂商父目录归一化为可删除项。

### 子 Bundle ID

XApp 沙盒入口及偏好入口使用其规则 loader 提供的子程序 ID。其沙盒闭包 `0x100073fb0` 只拼接 Containers 根与候选 ID、检查存在性并追加具体项目。

本项目优先读取所选 app 内 `Contents/XPCServices`、`PlugIns`、`Helpers`、`Applications`、`Library/LoginItems`、`Library/LaunchServices` 中的 `.app` / `.xpc` / `.appex` / `.bundle` 元数据。子 ID 必须是主 ID 的点号边界子项，或签名验证后与主程序同 Team；有遍历数量和深度上限，跳过符号链接及 framework 深层遍历。经此独立验证的 `associatedBundleIdentifiers` 可参与常规归属核对；其他已安装 app 或副本仍拥有同一资源时保持保护。

这与把其他程序资源中的所有旧子进程名称直接当独占归属不同。

### 特殊 Chrome 缓存

XApp 打包配置仅有一个 `SpecialPaths` 条目：`com.google.Chrome -> cache -> ~/Library/Caches/Google/Chrome`。本项目通过厂商下一层发现该目录，而不是导入“Google 整目录可删”的规则；删除资格仍由原有所有者、引用和名称/元数据证据决定。

配置的 `ScanExclusions.cache = ["com.google.Chrome.app."]` 已移植为主浏览器的排除项：`com.google.Chrome` 不会因共享前缀认领独立 Chrome app shim / Web app 的缓存；若扫描到相应独立应用，应按其自己的身份归属。XApp 配置中的 support/preference 排除数组为空。

### 额外偏好 ID

XApp `AppPreferenceExtraScan` 的非空映射如下。完整资源保留在 `special-app-uninstall-rules.decoded.json`；此表只描述候选发现关系。

| 主 ID | 额外 ID |
|---|---|
| `com.logi.optionsplus` | `com.logi.optionsplus.driverhost`、`com.logi.optionsplus.logivoice`、`com.logi.cp-dev-mgr` |
| `com.bjango.istatmenus` | `com.bjango.istatmenus.agent`、`com.bjango.istatmenus.menubar.7`、`com.bjango.istatmenus.status`、`com.bjango.istatmenus6.extras` |

本项目在 `ApplicationAssociationPathRegistry.preferenceClues` 保存上述兼容发现关系。仅由该表支持、未被常规归属规则独立确认的偏好项使用 `.compatibilityHint` + `.referenceOnly`，显示“兼容规则发现的关联线索，尚未确认独占归属”。若已从 app 本身验证了子 Bundle ID，则按常规更强证据核对，不因兼容表降低已有证据。

### 进程映射与服务边界

XApp 资源的 `AppProcessKillMapping` 包含 Logitech、iStatMenus、Better365 的 `childProcesses` / `helperProcesses` / `helperTools`，部分产品声明 `scanSubAppPaths = ["Contents/Applications"]`。静态解析证明这些字段存在，不证明每条映射在运行时被执行。

本批次**没有照搬进程 kill 表，也没有通过该表终止进程、启动应用、执行卸载脚本或删除 helper**。可独立从包内元数据识别的子组件已由子 Bundle ID 扫描覆盖；启动服务解析 `Program` / `ProgramArguments` 的绝对路径用于引用核对，plist 不会被执行。服务、特权 helper、插件、StartupItems 和 receipts 作为只读关联保留，需原安装来源或正确注销流程处理。

## 同时补充的其他目录

除上述 XApp 固定根外，目录表还覆盖用户/全局 `Preferences/ByHost`（仅匹配 `<Bundle ID>.<UUID>.plist`）、用户 `Group Containers`、Cookies、Autosave Information、Scripts、全局 Receipts 和 PrivilegedHelperTools，以及用户/全局 QuickLook、PreferencePanes、Services、Internet Plug-Ins、Input Methods、ScriptingAdditions、Screen Savers、Spotlight、Audio/Plug-Ins 的 Components/VST/VST3/HAL。

- 插件、索引、脚本/服务等注册组件与全局内容只读展示；发现名称不能替代注销流程。
- Group Containers 使用经签名验证的 application-groups 声明区分真实关联；其他已安装所有者/应用副本仍持有时不可删，仅凭 `group.<ID>` 名称不授权。
- 临时/缓存目录使用当前用户真实的 Darwin cache/temp 根，只匹配精确 ID 的直接子项，不扫描其他用户或整个 `/var/folders`，不相信任意 TMPDIR 环境值。
- 这些补充来自本项目的常见 macOS 关联范围设计，不宣称全部是 XApp 已观察到的功能。

## 核对与限制

`Sources/CoreContractChecks/ApplicationAssociationRootsContract.swift` 包含隔离临时目录中的 RawTherapee 三项候选（本体、Containers、空 Application Scripts）、逐项选择/恢复、未知/共享/引用/服务/全局资源保护等覆盖检查。本文件记录证据和实现映射；最终测试、构建、安装包和版本结果由本交付批次的验证记录给出，本文不代替运行结果。

静态已观察：11 个入口调用、目录构造和匹配、规则 loader 读取 bundle 资源并通过 property-list/JSONDecoder 解码、打包 plist 的实际内容。方法迁移属于本项目设计，删除保护来自本项目源码，不声称 XApp 具有相同保护。

保留未知：Hopper 无法给出完整原始函数体范围，调用引用可能不包含未解析目标；静态反编译不是原始源码，也未观察权限和删除行为。`SpecialAppUninstallRules` 字面量已在 `0x100140100` 找到，但针对该 typed string 的入向 xref 返回空，因此构造器将精确文件名赋给 loader 字段的绑定仍是间接证据；类名、schema、资源和读取链彼此支持。该局部限制不改变已观察的 24 个固定根，但不应宣传恢复了 XApp 全部内部实现。

## 入口证据索引

- E1：`0x100073bcc`，`ev_5664b6a09c52d78844ee7c21a612b0e829d90916a6ed3abc188c47dd3022a869`，[function-100073bcc.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100073bcc.json)。
- E2：`0x100073ccc`，`ev_e0cc689342172b863d5f41decb77f4c950314d99c2a5af8b2b7035ff84104d47`，[function-100073ccc.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100073ccc.json)。
- E3：`0x100075b8c`，`ev_7ca7ee26b24c7b732d50b97e3e324bb96e6612da1afd7a3faf581dd08cede933`，[function-100075b8c.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100075b8c.json)。
- E4：`0x1000762d4`，`ev_ab1b14738a2e7380cb632a435ffe2b7ce7172c208aaf2dd0f9c6c1196f0092c0`，[function-1000762d4.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-1000762d4.json)。
- E5：`0x100076ce8`，`ev_cfa0d3bd0206f421d9e4827ad619b5794fca4b85ea6fdfd2ab760e299a01227c`，[function-100076ce8.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100076ce8.json)。
- E6：`0x100076f5c`，`ev_b89c613ab4ad157e476c6ef2e0a14d6829a3461c16fbdd7c6072e1abd55eb38b`，[function-100076f5c.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100076f5c.json)。
- E7：`0x10007759c`，`ev_5e9e339b54be4649c8e8924c05775e38fb43eee6f1606ca47e87d45bdcf0342e`，[function-10007759c.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-10007759c.json)。
- E8：`0x100077a80`，`ev_5cdea0ea395737caa4e6de4100662d5fbcd02dc03e9ed51bda05d1226de3818f`，[other-files-function.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/other-files-function.json)。
- E9：`0x100077dc8`，`ev_ada96abaa02a39adc43e6b7f479cee0a47bc1985e10c455faf3e0e2b06b2acd6`，[function-100077dc8.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100077dc8.json)。
- E10：`0x100078af4`，`ev_c362d03ff068c362478c0aa6c567caa4ff39a114aef26d039ae7f8e35ad9b848`，[function-100078af4.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100078af4.json)。
- E11：`0x100078cb4`，`ev_5dcfaf16d51d29a7ba98d5aca0160bdf25998337e938ad73c3d8104158121d9d`，[function-100078cb4.json](/Users/bytedance/.codex/visualizations/2026/10/28/01a18231-0c00-7201-8362-5bc5e9a2577f/xapp-rea-20261029/coverage-audit/function-100078cb4.json)。

补充函数、静态数组字节、资源 reader 和有界负向搜索证据见保留目录中的 `roots-ledger.md` 和 `evidence-index.json`。全局启动服务根静态数组 `0x1001bd510` 由 REA read-bytes 完整读取，Evidence `ev_90a38f6f943f3b73b81b06854b24ffb6798facab1a3d2712099f841dca314745`；资源内容散列见 `resource-provenance.json`。
