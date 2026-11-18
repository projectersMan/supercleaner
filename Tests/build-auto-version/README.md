# 编译入口自动递增版本

用户最新要求取代旧的按修改批次手动 bump：每次 build-app.sh 通过基础检查并进入编译前，都自动分配一次下一 patch 和构建号；重复编译也会递增。单独测试、verify、create-dmg 和 publish 不递增。不新增跳过递增开关。

## 逐文件复核

| 文件 | 修改与必要性 |
| --- | --- |
| [Scripts/build-app.sh](../../Scripts/build-app.sh) | 删除原先只读 resolve 的版本块，在首次 Swift 编译前调用一次 next-build；基础签名/资源/SDK检查先通过。标量赋值捕获版本工具错误并受 set -e 终止，同次返回值供 App/Helper 共用；日志打印实际版本。 |
| [Scripts/version.py](../../Scripts/version.py) | 新 prepare_build/next-build 复用 patch increment、CI resolve 与原子保存，先完整校验再写入。CI版本须为下一patch，CI构建号须大于旧号并写回配置，随后只读发布无需另一个版本来源。resolve 保持只读，错误说明给出实际期望版本。 |
| [Tests/test_version.py](../test_version.py) | 增加连续自动递增、只读 resolve、无效 CI 不写入、CI 构建号持久化及后续单调递增回归。所有临时目录放在本批 Tests 下并自动清理。 |
| [Version.json](../../Version.json) | 只由本次正式 build-app.sh 自动写入，没有在构建前手动 bump。 |
| [README.md](../../README.md) | 用户运行方式与自动递增行为、当前产物入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 单一版本来源、校验/原子分配与冻结打包值，避免 App/Helper/发布分离。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 替换旧手动/重复编译不递增规则，说明 CI 输入是下一版本、失败号码保留和验证/打包不递增。 |
| [计划](../../doc/build-auto-version-plan.md)、本目录 | 记录设计反思、评分、逐文件理由和实际验证证据，历史交付记录不改写。 |

无新依赖；Python 只用已有标准库，主体 Swift 不要求 conda 或新 requirements.txt。根目录无 AGENTS.md 或 .trae/rules/project_rules.md，沿用当前工作区，保留全部前序未提交修改，不提交或推送。局部自动接线 100/100、失败保护/单调 CI 构建号 99/100，全局同一版本来源 100/100，均实施，无额外扩展。

## 定向回归与独立复查

- [红灯](red.log)：旧代码的 11 项测试中新增 3 项实际失败（缺少 next-build/prepare_build）。[绿灯](green.log)：11 项全部通过。
- [真实编译入口无效参数预检](invalid-build-preflight.log)：复用旧 CI 构建号时明确非零退出，尚未进入编译，Version.json 字节不变。
- 独立只读复查通过，确认 version 工具先校验后原子保存、zsh 错误传播、App/Helper 共享冻结值、发布端继续只读解析并核对已构建 App。提示的旧版本文档已按新要求更新。
- 初始版本快照：[version-before.json](version-before.json)。[实际构建日志](package.log)已记录从0.4.13（127）自动到0.4.14（128），没有另运行手动 bump。

## 最终验收

- [完整固定证书构建](package.log)：305 项 Release 测试、0 失败，1271 条双语检查及核心契约通过；日志中的自动版本分配恰好一次。
- [包验证](verification.log)、[DMG创建与挂载检查](dmg.log)通过；[安装及镜像核对](installation.log)确认 App/Helper、安装版及 DMG 中均为 0.4.14（128），三个可执行文件一致，严格签名及既有 entitlement 保留。
- [编译前快照](version-before.json)为 0.4.13（127）；[编译后快照](version-after-build.json)、[打包后快照](version-after-package.json)均为 0.4.14（128）。verify、DMG、安装和原生查看后配置仍逐字节一致。
- 原生设置页确认 0.4.14 / 128，随后回到空闲清理中心，未启动扫描或清理，没有更改权限、Helper 或清空废纸篓。自身旧安装备份、测试临时目录与旧自检 Home 已清理。
- [发布记录](../../doc/release-0.4.14.md)同步最终产物；逐文件差异、链接与版本证据见 [最终审计](final-audit.log)。没有提交或推送。
