# 独立增量复核

按本轮四份 before 快照审查，未将历史 dirty 改动或旧失效夹具计入本轮。

发现并处理：

1. 明确退出已发出 willTerminate 后，系统继续关闭窗口，触发第二次关闭提醒。原生 trace 完整复现 false 确认 → willTerminate → true 确认。修复为 Controller 同步订阅 willTerminate，weak self 设置终止标记并清 pending；关闭入口先检查标记，不在 requestTermination 早期提前置位。
2. 勾选抑制后清空失败，旧文案仍声称提醒开启。改为“未记录清空成功”，同步四条双语资源，尊重用户偏好。

复核：未发现新的确定问题。扫描仅允许提示，清空门禁完整、无排队永久删除；抑制恢复不改成功计量；手动与明确退出不带 checkbox；观察器不替换窗口 delegate。真实进程退出日志已无第二次确认，关闭同意后的成功/失败及偏好检查已接入并通过。

边界：reviewer 只读源码及日志，不运行 Finder 或用户真实 App；文档同步由主任务负责。UI截图连接失败不作为已完成视觉验证。旧 Tests/trash-close-reminder/main.swift 在本轮前已经失效，不属于本轮通过证据。
