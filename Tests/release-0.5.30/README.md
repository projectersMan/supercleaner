# 0.5.30 打包与本机安装

2026-11-22 按用户要求，将标题修改与清理中心统计同步一起交付。

## 验证

- [build.log](build.log)：标准构建脚本自动递增版本至 0.5.30（175）；核心契约、357 项 Core + 26 项 App Release 测试通过，使用固定本地证书完成签名。
- [verify.log](verify.log)：应用结构、最低系统版本、双语、签名、扫描/清理、导航、权限提示及废纸篓合成自检全部通过，未执行真实文件清理。
- [dmg.log](dmg.log)：首次制作镜像遇到“资源忙”；[dmg-retry.log](dmg-retry.log) 记录同脚本重试成功，应用签名、Applications 快捷方式与图标校验通过。
- [installed-signature.log](installed-signature.log)：安装副本通过完整签名验证。
- [install-verification.json](install-verification.json)：逐文件 SHA-256、目录及符号链接目标核对，共 203 项完全一致，版本 0.5.30（175），标题与统计中英资源均存在。
- 原生界面：退出旧版后打开 `/Applications/SuperCleaner.app`，已观察到 `Reclaim your Mac. Clear the AI clutter.`。

## 逐文件复核

| 文件或产物 | 本次修改原因 |
| --- | --- |
| [Version.json](../../Version.json) | 标准构建递增版本/构建号，用于区分已安装新版。 |
| [SuperCleaner.app](../../build/SuperCleaner.app) | 从当前源码重新生成并签名，包含标题和统计修改。 |
| [SuperCleaner-0.5.30.dmg](../../build/SuperCleaner-0.5.30.dmg) | 提供经过挂载校验的新版安装包。 |
| [README.md](../../README.md) | 更新当前版本、安装位置和产物链接。 |
| [doc/architecture.md](../../doc/architecture.md) | 标明当前交付版本，区分历史说明。 |
| [doc/development.md](../../doc/development.md) | 记录本次正式构建和验证结果。 |
| [功能实施计划](../../doc/dashboard-module-metrics-plan.md) | 补充正式交付状态。 |
| [功能验证记录](../dashboard-module-metrics/README.md) | 将源码阶段“未安装”更新为本次交付结果。 |
| [版本说明](../../doc/release-0.5.30.md) | 汇总本版功能、验证及安装结果。 |
| 本目录日志与核对结果 | 保存构建、镜像和安装证据。 |

原有未提交源码与文档修改保留；本次未额外改动业务代码、依赖或签名策略，未提交/推送。成功安装并打开后已清理临时旧版备份与测试生成的空资源索引。

反思：终端受限环境无法完整读取证书信任信息，安装签名应在与正式构建相同的本机证书环境下核验；框架符号链接不适合直接递归 diff，故用不跟随链接的文件哈希与链接目标清单做一致性核对。

局部建议“确认实际运行的是新版”100/100，已实施；全局建议“让构建包、安装包与本机安装保持同版可核验”98/100，已实施。无新增依赖，无需修改 requirements.txt。
