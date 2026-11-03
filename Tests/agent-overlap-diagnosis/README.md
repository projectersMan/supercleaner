# Agent 覆盖关系定向验证

在项目根目录运行 `zsh Tests/agent-overlap-diagnosis/run-contract.sh`。需先按 [打包脚本](../../Scripts/build-app.sh) 构建本机 App，供验证调用独立的 AgentInference；模型使用仓库中的随包权重，支持 macOS 14+ / arm64。

- `analysis-contract.swift`：真实模型计算7个相同能力Skill和2个MCP；核对Top 3、排除自身、默认85%预选时保留覆盖来源、明确保留及缓存复用不再推理。
- `label-contract.swift`：直接渲染生产组件 [AgentContainmentLabel.swift](../../Sources/CleanerApp/AgentContainmentLabel.swift)，生成可见状态与Top 3快照供视觉核对。快照生成成功本身不代表文字已经通过视觉验收。
- `run-contract.sh`：构建并执行以上验证，生成的程序、夹具索引与快照仅写在本目录；不修改用户真实索引，不执行清理，不连接MCP服务。

本机全量重建及交付结果记录在 [修复计划](../../doc/agent-overlap-repair-plan.md)，逐文件必要性记录在 [授权范围审计](../../doc/agent-only-scope.md)。

预选检查另覆盖共享源保留、无索引缓存预选、明确保留与清理资格、待删缓存不作为覆盖来源。0.2.34批次更新检查源码，但未运行测试。
