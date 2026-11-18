# 0.4.29 (143)

关闭窗口的清理提醒增加“不再提醒”，可在 Settings → Cleanup Reminders 恢复。手动 Empty Trash 始终确认且不带该选项；抑制不表示已清空。

修复 Project 已清理而 Agent 仍扫描时关闭没有及时提示：提示与清空资格分离，扫描继续后台；关闭提醒立即显示，清空按钮继续禁用并说明扫描结束后可操作，不排队永久删除。清理执行本身或其它互斥状态仍保留一次待处理提醒。

明确退出后系统关闭窗口不再触发第二次提示；Cancel 仍可保留 Trash 并完全退出。同意清空后的失败文案尊重提醒偏好，不虚称提醒开启。

正式构建自动升版，318 项测试、Core contracts、包自检与稳定签名通过。SDK 27.2 / 最低 macOS 13.0 保留。App 与挂载 DMG 的版本、权限、三个可执行文件哈希一致。

[SuperCleaner-0.4.29.dmg](../build/SuperCleaner-0.4.29.dmg)，SHA256 `5a4982f5290d2faa3699f451035e920e07989bc9c2a7115c61782be28dbc527a`。

保留用户正在运行的 0.4.28 扫描，未关闭或自动替换安装；安装新包后测试。原生配置与状态回归通过，独立 Modal 截图连接失败，未计为已完成视觉验证。无真实清空、权限修改、提交或推送。

[实施计划](close-trash-reminder-choice-plan.md) · [逐文件验证与边界](../Tests/close-trash-reminder-choice/README.md) · [独立复核](../Tests/close-trash-reminder-choice/review.md)
