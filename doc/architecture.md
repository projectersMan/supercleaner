# 架构与卸载资格

SuperCleaner 使用 Swift 6 和 SwiftUI 构建 macOS 应用，核心扫描、计划和执行逻辑位于 [CleanerCore](../Sources/CleanerCore)，界面与状态协调位于 [CleanerApp](../Sources/CleanerApp)，受限管理员操作位于 [CleanerHelper](../Sources/CleanerHelper)。完整项目架构见 [现有架构文档](../docs/architecture.md)。

应用卸载链路为 [发现](../Sources/CleanerCore/ApplicationScanner.swift) → [分析](../Sources/CleanerCore/ApplicationUninstallAnalysis.swift) → [计划](../Sources/CleanerCore/UninstallPlanner.swift) → 用户选择与确认 → [实时复核](../Sources/CleanerCore/ApplicationExecutionValidator.swift) → [执行](../Sources/CleanerCore/Execution.swift)。

- 系统保护：字面或实际路径在 `/System/` 中的系统应用，仅在 Protected 和 All 可见，不提供退出或卸载复选框。
- 运行状态：非系统应用正在运行时只进入 Running，未运行时只进入 Uninstallable，三个非 All 范围互斥；退出后复用预备卸载清单，重新启动后移回 Running 并清除卸载选择。
- 执行权限：不再将只读模式或父目录权限持久化为不可卸载状态，实际权限错误进入既有授权/重试流程。
- 第三方输入法：`/Library/Input Methods`、`~/Library/Input Methods` 中 app 本体可显式卸载；系统输入法、通用缓存清理保护、共享内容保护和用户保护清单继续生效。

本次改动与验证见 [实施计划](application-uninstall-eligibility-plan.md) 和 [逐文件复核](../Tests/application-uninstall-eligibility/README.md)。

当前本地打包版本为 0.4.3（117），见 [本次打包记录](release-0.4.3.md)；上一版本的 App、Helper、DMG 与安装副本验收见 [0.4.2 打包记录](release-0.4.2.md)。

## 清理后的关闭提醒

[TrashReminderState](../Sources/CleanerCore/TrashReminderState.swift) 以 AppModel 的本次累计清理字节数和 UserDefaults 偏好判断是否提醒，并记录本次会话已确认的容量；重新扫描不重置，新增清理后允许再次提醒。“不再提醒”跨重启保留。

[TrashReminderWindowObserver](../Sources/CleanerApp/TrashReminderWindowObserver.swift) 仅监听挂载的主窗口关闭，不替换 SwiftUI 窗口 delegate；[应用退出回调](../Sources/CleanerApp/CleanerApp.swift) 通过更新退出门禁后复用同一个 [TrashReminderController](../Sources/CleanerApp/TrashReminderController.swift)。原生弹窗提供打开废纸篓、继续关闭/退出和关闭提醒选项，不执行清空操作；累计容量包括恢复区内容，文案不承诺清空废纸篓能释放全部累计容量。
