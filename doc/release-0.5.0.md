# 0.5.0（145）

汇总上次提交以来的六维度扫描、清理交互和打包改动。

- 新增 Local AI Models 与 Project Artifacts。模型由用户手动选择；项目产物预选遵循活动、Git 与路径检查，Git 跟踪产物手动选择及可选预选设置保留。
- 项目扫描根目录可在设置中配置多条，列表展示三行后滚动。项目内 DMG 发现与归属由 Project 统一处理，其余安装包留在大文件维度。
- 六模块独立扫描提示、取消与继续；默认清理队列汇总各模块已完成结果，避免后到结果覆盖先前默认项。项目保留 All、Protected、Selected，自动展示 Selected 或回落 All。
- Disk Space 移至侧边栏底部，Elapsed 位于扫描按钮右侧；侧边栏与底部操作栏背景统一，使用实际 SDK 的原生分栏样式。优化应用卸载首次进入的保护检查和计划准备。
- Empty Trash 统一由 Finder 执行并确认结果，允许与只读扫描并行。关闭提醒支持“不再提醒”和设置恢复，Cancel 保留用户不清空直接退出的选择。
- 删除未使用 CLI；打包保留 App、Helper 和独立 AgentInference，固定模型、许可及稳定签名校验。

`./Scripts/build-app.sh --version 0.5.0` 精确生成本版，构建号由 144 增至 145；后续普通编译自动使用 0.5.1。版本显式目标、非法值不写入与后续递增均有回归覆盖。

[安装包](../build/SuperCleaner-0.5.0.dmg) · [验证与逐文件审查](../Tests/release-0.5.0/README.md)

318 项 Release 测试、13 项版本测试、Core contracts、包内自检及关闭/退出原生回归通过。DMG 大小 299,014,026 字节，SHA256 `b2a1281026ddf0949902c998f0d1e4eb6e037ede95c2d6ced3ac0e60efb5cdfe`；App 与镜像内元数据、三个可执行文件哈希和严格签名一致。本次不替换运行中的安装，不执行真实 Trash 清空或用户内容删除；仓库推送不等于 Apple 公证或自动更新渠道发布。
