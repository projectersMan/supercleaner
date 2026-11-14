# 开发与验证

完整开发指南见 [现有开发文档](../docs/development.md)。本项目主体为 Swift，不使用 Python conda 环境；依赖声明保持在 [Package.swift](../Package.swift)，本次未新增依赖，也没有需要更新的 `requirements.txt`。

本次遵循先计划、再复现、后修正、最后验证的流程，详见 [计划](application-uninstall-eligibility-plan.md)。导入放在文件顶部，不新增函数内定义或动态安装逻辑，不通过捕获错误掩盖失败。验证素材集中放在 [Tests](../Tests)。未发现根目录 `AGENTS.md` 或 `.trae/rules/project_rules.md`，不凭空创建工作流规则文件。

卸载相关修改须同时检查发现、筛选、分析、计划、实时复核、授权、恢复、界面勾选及文案，不能只放开列表却保留后续错误拦截。系统保护和运行状态必须分别建模；实际权限不足不得被静态预检永久归类为不可卸载。

Protected、Running、Uninstallable 必须构成应用清单的互斥分区：系统应用优先归入 Protected；其余应用根据是否运行分别进入 Running 或 Uninstallable。All 只是完整汇总。回归须验证三个范围无重复、无遗漏，并覆盖启动/退出迁移；Uninstallable 不显示退出按钮。

验证命令：

```sh
swift test
swift run CoreContractChecks
SUPERCLEANER_REQUIRE_STABLE_SIGNING=1 ./Scripts/build-app.sh
```

真实应用验证只构建卸载计划，不执行卸载或退出用户应用。详细结果及边界见 [验证记录](../Tests/application-uninstall-eligibility/README.md)。开发验证阶段没有提交或推送；用户后续明确要求的远程同步范围见 [版本记录](release-0.4.3.md)。

版本统一由 [Version.json](../Version.json) 管理，使用 `/usr/bin/python3 Scripts/version.py bump` 每批仅递增一次。本次关闭提醒升级为 0.4.3（117）；构建成功后使用 [create-dmg.sh](../Scripts/create-dmg.sh) 生成带版本号的 DMG，再挂载核对 App/Helper 版本与构建产物一致，见 [本次打包记录](release-0.4.3.md) 和 [上一版本记录](release-0.4.2.md)。

关闭提醒的实现与验证见 [计划](trash-close-reminder-plan.md) 和 [验证记录](../Tests/trash-close-reminder/README.md)。提醒资格必须使用 `sessionCleanupSummary.bytes`，0 字节不显示；已确认容量只在当前会话去重，“不再提醒”使用 `cleanup.suppressTrashReminder` 持久化。主窗口关闭与直接退出必须共用状态，最小化或其他窗口关闭不提醒，更新禁止退出时不得显示退出提醒。不得替换 SwiftUI 窗口 delegate，不得自动清空废纸篓或将清理累计量视为已释放空间。修改中英文资源后运行 `python3 Scripts/check-localizations.py`，定向回归为 `swift test --filter TrashReminderStateTests`。没有新增外部依赖。
