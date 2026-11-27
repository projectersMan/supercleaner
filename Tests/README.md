# 测试入口

| 入口 | 覆盖范围 |
| --- | --- |
| CleanerCoreTests/ | 扫描、归属、计划、保护、模型、执行和恢复 XCTest |
| CleanerAppTests/ | 首页计量、跨维度计划、项目保护、界面状态与容量 XCTest |
| test_version.py | 版本校验、递增及失败写入边界 |
| test_signing.py | 默认临时签名、可选严格模式、缺失固定身份及严格打包拒绝 |
| NativeChecks/run-checks.sh | 原生 Trash/退出回归；可选图标、Agent、签名检查 |
| Performance/AgentProfile.swift | 使用独立输出目录的 Agent 存储和分析性能探针 |
| Performance/AgentProtectionBenchmark.swift | 完整 Agent 扫描计时及逐字段摘要对照；前后版本使用同一目录、固定时间，忽略扫描新建 UUID 和集合顺序 |
| FixtureTools/make-large-files.py | 在 temporary/ 下生成隔离大文件、ZIP 和重复输入 |
| ../Scripts/check-artifacts.py | 统一 App/DMG/可选已安装副本的只读一致性检查 |
| ../Scripts/verify-standalone.sh | 隐藏编译目录后的包内资源及真实推理运行时验证 |
| ../Scripts/check-doc-links.py | 当前文档的仓库内链接检查 |

完整命令和构建前提见 [开发指南](../docs/development.md)。原生检查默认依次运行 `trash`、`quit` 和 `termination`；也可单独指定 `icons`、`agent`、`signing`。默认不执行用户内容删除。缺少指定本机夹具或固定签名时的跳过/失败不计为通过。

自定义模型目录回归见 [CustomModelPathTests](CleanerCoreTests/CustomModelPathTests.swift)、[OllamaModelCleanupTests](CleanerCoreTests/OllamaModelCleanupTests.swift) 和 [CustomModelSettingsTests](CleanerAppTests/CustomModelSettingsTests.swift)，覆盖配置持久化、坏配置隔离、固定与自定义并存、撤销执行资格、链接保护和原根恢复。可用 `swift test --filter 'CustomModel|OllamaModelCleanupTests'` 单独运行。

所有生成物只写入 `Tests/temporary/`。历史修改和验证结论见 [历史归档](../docs/history.md)；交付后清理旧探针、脚本、临时夹具和过渡安装包，保留当前产物与必要核验记录。

[ProjectInstallerTests](CleanerCoreTests/ProjectInstallerTests.swift) 增加隐藏项目 DMG 的预选开关、清理恢复、重复副本/父目录保留、凭据目录、应用包、链接与永久保护回归；仅使用隔离夹具。

[ProjectModuleOwnershipTests](CleanerCoreTests/ProjectModuleOwnershipTests.swift) 覆盖项目/Agent/大文件六种完成顺序、9.76GB 容量与目录归属、真实保护及模型手选优先级；[ProjectModuleSelectionTests](CleanerAppTests/ProjectModuleSelectionTests.swift) 覆盖 Agent 后发布时项目行、默认选择、手动取消和底栏容量。实际渐进发布入口由原生资源自检与 XCTest 共同验证，确保按路径合并后 Agent 选择同步不撤销其他模块的选择。

模型目录设置的空列表直接收起，添加后恢复原有滚动列表；移除最后一项时仍须可保存空配置、撤销或显示读取错误。配置保存/读取由现有 CustomModelSettingsTests 验证。

`AgentProtectionBatchTests` 覆盖 Agent 批量保护的跨批次、末批、路径重定向和执行时新增保护；取消与有界并发由 `AgentScanAccelerationTests` 验证。`PythonEnvironmentArtifactTests` 覆盖公开 CA 证书、与安装 RECORD 哈希和大小一致的依赖 SSL 测试 PEM、清理恢复，以及改动或新增凭证仍拒绝执行。
