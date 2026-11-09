# Agent功能实施与范围收敛

以origin/main的75c9c262b46ae41e3e99daef6fb0d0225056885c为基线。当前仅保留[能力包含设计](agent-skill-overlap-analysis-design.md)所定义的Agent界面、Skill/MCP能力覆盖、前5来源、去重累计预选、稳定身份缓存及显式重算功能。

0.2.24曾把“未要求的部分不变”误解为回退所有非Agent变更。用户现已明确：恢复首页布局固定、四行导航、标题栏对齐和四模块独立取消/继续扫描。CLI契约、扫描算法、文件恢复与发布脚本仍保持远端。完整逐文件说明、函数核对及交付证据见[Agent范围审计](agent-only-scope.md)。

新增模型库本身最低要求macOS14，不能继续让它抬高整个应用平台要求。因此保留主应用/Helper/CLI的macOS13配置，通过独立AgentInference可执行包承载固定GemmaEmbed依赖；根依赖锁文件与远端一致。该进程仅供Agent语义分析使用，模型、许可及进程随App打包，不修改其他模块。

本批只递增patch/build一次，不新增或运行测试，不提交代码，不改写用户真实索引。最终App、DMG及范围审计在交付前核对。

## 0.3.8 显示范围

- 将显示筛选的初值设为「已选中」。局部 100 分，直接对应用户操作。[AppModel.swift](../Sources/CleanerApp/AppModel.swift)
- Skill 和 MCP 共用同一筛选状态。全局 98 分，继续由一个初值控制两个列表。
- 使用说明记录如何切换到「全部」。[README.md](../README.md)
- 架构文档记录两个列表共用筛选的行为。[architecture.md](../docs/architecture.md)
- 递增补丁版本和构建号。[Version.json](../Version.json)
