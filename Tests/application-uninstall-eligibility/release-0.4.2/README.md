# 0.4.2（116）构建与安装包验证

使用既有版本脚本从 0.4.1（115）递增一次，重新生成固定证书签名 App 和版本化 DMG。

- [构建日志](build.log)：核心契约、Release XCTest、App/Helper/CLI 编译和打包门禁。
- [verify.log](verify.log)：既有 App 结构、资源、签名、双语、恢复烟雾测试和模型自检，全部通过。
- [dmg.log](dmg.log)：DMG 创建、图标、Applications 快捷方式与镜像内签名验证通过。
- [verification.txt](verification.txt)：App、Helper、DMG 内副本、安装副本的最终版本/签名/内容一致性与镜像 SHA-256。全部为 0.4.2（116），设置页已实机确认。

所有本批额外验证材料、挂载目录和临时目录均在本目录，结束后清理空临时目录。没有新依赖、git 提交、推送或远程发布。

代码回归来源已确认：`bb7e07a` 的 Uninstallable 原本就含 `!isRunning`；本次对话中去掉该条件引入重叠，现已恢复。分类回归和实机验收见 [上级记录](../README.md)，本批仅升级版本、重新编译和打包。
