# 0.4.3（117）本地交付

- 本次增加清理后的关闭/退出提醒及持久“不再提醒”，用户反馈后的正文为“本次已清理 {0}，清空废纸篓以释放空间。”
- [Version.json](../Version.json) 从本批开始时的 0.4.2（116）递增一次；App 与 Helper 均为 0.4.3（117）。
- [SuperCleaner.app](../build/SuperCleaner.app) 使用既有固定证书签名，`codesign --verify --deep --strict` 与 [完整包验证](../Tests/trash-close-reminder/package-verification.log) 通过。
- [SuperCleaner-0.4.3.dmg](../build/SuperCleaner-0.4.3.dmg) 已生成；脚本重新挂载检查包签名、图标和 Applications 拖拽入口后卸载。
- 更新前通过界面确认旧安装副本没有运行中的清理，正常退出后替换 `/Applications/SuperCleaner.app`；版本和签名核对通过，并从固定路径正常启动。应用数据与原有偏好保留。
- 264 项完整测试和 release 测试、核心契约、3 项新增状态回归、跨进程偏好与原生交互验证通过，详见 [逐文件复核](../Tests/trash-close-reminder/README.md)。
- 未清空废纸篓，未执行用户文件清理，未提交或推送。

2026-11-14 按用户要求重新编译打包，沿用 0.4.3（117）；264 项测试、签名与完整包验证通过，已重新生成同名 DMG，见 [本次构建记录](../Tests/rebuild-2026-11-14/README.md)。本次没有源码修改或安装副本更新。

## 2026-11-14 远程提交范围

本次按用户明确要求统一整理自 `bb7e07a` 以来的修改，远程同步目标为 `origin/main`：修正卸载分类、第三方输入法资格、授权恢复与 Helper 执行前校验，增加清理后的关闭提醒、持久“不再提醒”及精简双语文案，并包含测试、文档和验证记录。逐文件原因见 [卸载资格复核](../Tests/application-uninstall-eligibility/README.md) 和 [关闭提醒复核](../Tests/trash-close-reminder/README.md)。

提交前再次运行完整 `swift test`，264 项、0 失败，见 [推送前测试日志](../Tests/rebuild-2026-11-14/prepush-test.log)。版本保持 0.4.3（117）；构建目录沿用现有 `.gitignore`，不重复纳入 Git。
