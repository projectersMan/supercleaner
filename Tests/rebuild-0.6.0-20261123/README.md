# 0.6.0 同版本重新构建

2026-11-23，按用户要求重新编译安装包，并覆盖远程最后一次推送。初始工作区干净，本地及远程 `main` 均为 `371ec18aa8e796a4a4699ec2f141af5c76d9b22c`。

## 构建范围

保留已确认的 0.6.0（176），不改变业务源码及依赖。先分别清除主工程和 AgentInference 的 Swift 编译产物，再复用 [标准构建流程](../../Scripts/build-app.sh) 完整编译、测试、组装及签名。临时驱动位于 `Tests/temporary/`：仅把脚本目录指向原 Scripts、把版本自动递增改为读取已有版本，其他步骤保持一致；完成后删除该临时驱动。

本次交付对象是重新生成的 DMG；2026-11-22 的本机安装记录见 [前次验证](../release-0.6.0/README.md)，作为历史证据保留，不将它充作本次重新构建产物的一致性证明。

## 验证材料

完整构建完成，357 项 Core + 26 项 App Release 测试零失败；核心契约、1300 条双语检查、签名及完整应用自检通过。DMG 首次生成即成功；额外只读挂载逐项比较后，203 个文件、目录及链接与本次构建完全一致，App 与 Helper 均为 0.6.0（176），镜像已卸载。

- `build.log`：清除缓存后的完整 Release 构建、测试、核心契约和签名。
- `verify.log`：应用结构、签名、双语及扫描、清理、导航等自检。
- `dmg.log`：生成安装包及只读挂载验证。
- [artifact-verification.json](artifact-verification.json)：重新构建的版本、主程序与安装包校验和、包内一致性结果。
- `lfs-progress.log`：安装包上传进度；日志沿用仓库既有忽略规则。

## 逐文件复核

| 文件 | 修改原因 |
| --- | --- |
| [SuperCleaner-0.6.0.dmg](../../build/SuperCleaner-0.6.0.dmg) | 替换为本次从清空的编译缓存生成并验证的安装包。 |
| [README.md](../../README.md) | 明确最新安装包重新构建日期，区分前次本机安装记录。 |
| [doc/architecture.md](../../doc/architecture.md) | 更新当前交付证据入口，架构及业务规则不变。 |
| [doc/development.md](../../doc/development.md) | 记录同版本重新构建流程和验证结果。 |
| [docs/architecture.md](../../docs/architecture.md) | 同步仍被引用的架构入口。 |
| [docs/development.md](../../docs/development.md) | 同步仍被引用的开发入口。 |
| [发布说明](../../doc/release-0.6.0.md) | 增补重打包记录，保留最初发布和安装事实。 |
| 本说明 | 保存本次过程、验收范围及逐文件必要性复核。 |
| [artifact-verification.json](artifact-verification.json) | 保存可独立核对的产物身份和一致性证据。 |

所有改动仅服务于同版本重打包与覆盖交付；无新增依赖，不需要 requirements.txt 变更。`.trae/rules/project_rules.md` 在本工作区不存在。

## 反思与已实施建议

- 局部：清除编译产物后再完整构建，100/100，避免把缓存命中误称为重新编译。
- 全局：独立核验 DMG 内容和校验和，98/100，确保远程产物可追溯到本次构建。
- 全局：覆盖前校验远程原提交，并使用指定旧提交的 `--force-with-lease`，100/100，避免覆盖期间出现的其他提交。

没有额外业务修改或需要扩展的低价值建议。测试使用隔离素材和合成回执，不执行用户真实文件清理。
