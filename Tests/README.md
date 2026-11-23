# 测试入口

| 入口 | 覆盖范围 |
| --- | --- |
| CleanerCoreTests/ | 扫描、归属、计划、保护、模型、执行和恢复 XCTest |
| CleanerAppTests/ | 首页计量、跨维度计划、项目保护、界面状态与容量 XCTest |
| test_version.py | 版本校验、递增及失败写入边界 |
| test_signing.py | 默认临时签名、可选严格模式、缺失固定身份及严格打包拒绝 |
| NativeChecks/run-checks.sh | 原生 Trash/退出回归；可选图标、Agent、签名检查 |
| Performance/AgentProfile.swift | 使用独立输出目录的 Agent 存储和分析性能探针 |
| FixtureTools/make-large-files.py | 在 temporary/ 下生成隔离大文件、ZIP 和重复输入 |
| ../Scripts/check-artifacts.py | 统一 App/DMG/可选已安装副本的只读一致性检查 |
| ../Scripts/verify-standalone.sh | 隐藏编译目录后的包内资源及真实推理运行时验证 |
| ../Scripts/check-doc-links.py | 当前文档的仓库内链接检查 |

完整命令和构建前提见 [开发指南](../docs/development.md)。原生检查默认依次运行 `trash`、`quit` 和 `termination`；也可单独指定 `icons`、`agent`、`signing`。默认不执行用户内容删除。缺少指定本机夹具或固定签名时的跳过/失败不计为通过。

所有生成物只写入 `Tests/temporary/`。历史材料中的重复安装/产物校验脚本、旧探针、逐批次日志和文档已合并到 [历史归档](../docs/history.md)，原始文件和哈希仍可恢复。
