# Agent 保护检查批量化与 Python 虚拟环境可选性修复

交付日期：2026-11-27。基线为开始分析时的 origin/main `71264f3e4a589ed1891c0b41d6a784619ffb3a6f`；源码修复阶段保持业务分支、Version.json 和运行中的应用不变；后续编译打包结果见文末。

## 实际修改

1. `Sources/CleanerCore/AgentScanners.swift`：资产遍历仍逐项执行原有路径安全检查；遍历结束、发布清单前，使用现有 ProtectionPolicy 数组接口每 128 项应用保护。每批重新解析保护根，每个候选重新解析当前物理路径，并按保护后的风险重算清理资格。取消检查、扫描预算、目录去重、Skill/MCP 解析与执行前复核保留。临时资产在保护完成前不会发布。
2. `Sources/CleanerCore/ProjectArtifacts.swift`、`ProjectPEMResources.swift`：公开 X.509 证书不再归为部署凭证；证书正文必须通过系统证书解析器验证。公开证书包上限 1 MiB，原有公钥的 64 KiB 限制不变。Python 虚拟环境内依赖附带的 SSL 测试 PEM，只有当前文件大小和 SHA-256 与安装 RECORD 完全一致，且路径、类型与保护检查通过，才可作为可重建资源；其他安装资源仅允许经过验证的公开证书包。RECORD 缓存仅存在于当前目录检查中，执行前重新加载。新增或改动的私钥、.env、未知 PEM、链接、用户保护项仍受保护。
3. 新增 `AgentProtectionBatchTests.swift`、`PythonEnvironmentArtifactTests.swift`，保留现有保护与执行回归；新增完整扫描计时/摘要探针 `Tests/Performance/AgentProtectionBenchmark.swift`，更新测试索引。

## 截图中不可选的原因与实际核验

旧规则把 236–613 KB 的 certifi/gRPC 公开 CA 证书包判为凭证，既有 64 KiB 大小限制，也不识别 CERTIFICATE 类型。iqalabel 另有 future 依赖附带的 SSL 测试私钥、DH 参数和空/异常证书样例；这些文件与依赖的安装 RECORD 哈希和大小一致。之前的简化 .venv 测试只有 pyvenv.cfg 与普通输出，未覆盖这些真实依赖资源。

修复前新增回归实际复现“不可选”和 project-changed 执行拒绝，修复后通过。三处真实目录的只读扫描及执行前检查结果：

| 项目 | .venv 大小（bytes） | 手动可选 | 执行复核 |
| --- | ---: | --- | --- |
| aitone | 2299663522 | 是 | 通过 |
| 3s-system-mvp | 1780097538 | 是 | 通过 |
| iqalabel | 1714499477 | 是 | 通过 |

该核验只将项目发现范围限定到所请求的 .venv 与项目标记；环境内部全部内容、Git 状态、路径和保护检查使用真实磁盘。未移动或删除这些目录，也未替换安装中的 0.6.23 应用。隔离夹具的清理与恢复另由 XCTest 验证。

## Agent 完整扫描性能

Apple M3 Pro / arm64，macOS 26.5.2，Swift 6.3.3，Release。fast-anything 不支持 Swift，本次使用原生生产扫描器。计时包含项目/能力发现、资产遍历、分类、保护和排序；摘要编码写盘在计时范围外。两版使用相同时间参数、相同扫描入口，不执行推理或清理。首轮指进程内缓存未建立，不表示清空了操作系统缓存。扫描期间未并行运行编译或另一扫描。

| 工作负载 | 修改前 | 修改后 | 耗时减少 |
| --- | ---: | ---: | ---: |
| 固定夹具，24,314 项，三轮中位数 | 7.403 s | 5.624 s | 24.0% |
| 真实用户目录，首轮，约 28.1 万项 | 136.811 s | 129.633 s | 5.2% |
| 真实用户目录，热轮，约 28.1 万项 | 108.560 s | 103.376 s | 4.8% |

固定夹具三轮分别为：旧版 7.648 / 7.403 / 7.369 s，新版 5.679 / 5.236 / 5.624 s。六份逐字段摘要完全一致，仅规范化每轮新建的候选 UUID 与集合顺序。覆盖资产全部候选字段、风险、证据、分类、活动状态、清理资格、Skill/MCP 完整记录、来源路径、覆盖状态与限制。

真实目录持续变化，不能将其描述为严格同输入：旧版两轮自身已有 8 项增加、2 项减少、82 项资产字段变化；对应新版两轮相比旧版分别有 3/3 项增加、29/35 项减少和 118/117 项资产字段变化，Provider 计数相应变化。两轮的全部 5,470 个 Skill、52 个 MCP、覆盖状态与完成标记均逐字段一致；四轮扫描 isComplete 均为 true。真实目录的 5.2% / 4.8% 是本机动态工作负载的观察值；严格一致性以固定夹具验收。

这些是 Agent 完整扫描的收益，不是整个六模块 App 的加速比。先前 7.1 倍是保护接口单步骤微基准，不用作完整扫描结论。

## 源码修复阶段验证

- Release 核心/探针构建通过；隔离 SwiftPM 包复制当前 CleanerCore/CleanerZIP，与当前工作区核心源码逐字节一致，不包含 GUI、推理 worker 或 Sparkle。
- 最后一次相关 Release XCTest：158 项、0 失败，9.05 秒。筛选范围为 Agent、Protection、Execution、ContentChange、PathPolicy、Planning、Project 和 PythonEnvironment。
- 包含跨 128/256 项边界、末批、不可用保护清单、预算限制、保护根重定向、候选路径变为受保护链接、扫描后新增保护、取消与有界并发。
- Python 回归包含公开 CA、大证书包、安装包测试样例、大小改变及大小不变的哈希改变、未记录私钥、非测试目录私钥、.env、链接、虚拟环境外资源、混合/损坏证书，以及新增私钥执行拒绝和隔离清理/恢复。
- 本地化检查 1,354 条通过；差异空白检查通过。
- 未运行完整 GUI/App 打包验收，未安装新应用，未提交或推送。

## 记录与复现

当前必要记录位于 `Tests/temporary/agent-protection-batch/`：comparison.json、environment.json、最终测试/构建日志、固定扫描时间、基线提交及 AgentScanners 副本、source-hashes.json。原始逐字段摘要压缩为各子目录 pass-N.jsonl.gz，未压缩内容 SHA-256 见 snapshot-sha256.json。三处真实 .venv 的只读核验记录在 `Tests/temporary/python-environment-artifacts/real-validation.jsonl`。

探针源码在 Tests/Performance/AgentProtectionBenchmark.swift。使用独立 SwiftPM 包，复制目标提交的 CleanerCore/CleanerZIP，将探针设为依赖 CleanerCore 的 executableTarget，以 `swift build -c release` 编译两版。调用方式：`benchmark <相同home目录> <独立输出目录> <相同context-unix-time> <重复次数>`。固定时间与相关文件树不变时，对照逐字段摘要；真实目录变化须单独报告。

本次临时包、编译缓存、二进制与固定扫描夹具已清理，保留必要核验记录。既有 build 目录删除状态保留。本批次完成后不启动其他优化。

## 后续编译打包交付：0.6.24（200）

按用户后续要求编译打包并准备提交远程。Version.json 由标准入口递增一次；构建期间核验并复用固定 Sparkle 2.10.0 缓存，续跑阶段读取同一版本，未修改构建脚本或依赖。

- 完整 Release XCTest 471 项通过（Core 409、App 62）；Python 版本/签名测试 18 项通过。
- CoreContractChecks、Sparkle 签名互操作、1,354 条本地化检查通过。
- 标准 App 签名、SDK、最低系统、双语、扫描/清理、导航、权限、响应与 Trash 自检通过；隐藏编译缓存后包内模型产生有限、非零的 768 维向量，缓存恢复。
- DMG 只读挂载后 196 个条目的类型、权限、内容及链接与 App 一致；App/Helper/Version.json 一致，镜像及签名验证通过，镜像已卸载。
- DMG 大小：299,715,373 字节；SHA-256：`ead064265285db8cf4cacf4c74762ec12ecf4efce2c69237000415c97714a76a`。
- CleanerApp 二进制 SHA-256：`75077674905837b8e640732888c16956d6f859350fe564260c9aa4e25875ee82`。
- 产物：`build/SuperCleaner.app`、`build/SuperCleaner-0.6.24.dmg`；采用既有 ad-hoc 本地签名，未安装替换本机应用。

本轮构建/完整测试、独立运行与镜像核验日志在本机 `Tests/temporary/release-0.6.24/`，不随仓库推送。提交包含修复源码、回归、文档、版本及 App/DMG，DMG 与模型沿用 Git LFS。
