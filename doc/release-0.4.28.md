# 0.4.28 (142)

用户可以保留垃圾箱并直接退出 App。明确退出时，原 Empty Trash 弹窗中的 Cancel 只取消清空，随后正常退出；选择清空则等待执行、容量刷新和必要错误说明结束，清空失败也不会否决退出。

单独点击 Empty Trash 的 Cancel 仍只取消清空；红色关闭仍只关闭窗口，App、扫描和会话在后台继续。没有新增弹窗、按钮、配置或依赖。

旧版把“是否清空成功”的 Bool 误当作退出许可，本版仅修正退出 delegate 的这个判断。原生 NSApplication 回归已先复现旧版 Cancel 后不退出，再验证修复后收到终止通知且进程结束；无真实 Finder 清空。

正式构建自动升版，317 项测试及包自检通过；稳定签名、SDK 27.2 / 最低 macOS 13.0 保留。已安装并打开 `/Applications/SuperCleaner.app`，build/安装/挂载 DMG 版本、entitlement 与三个可执行文件哈希一致。

安装包：[SuperCleaner-0.4.28.dmg](../build/SuperCleaner-0.4.28.dmg)。SHA256：`356b7e7d83534c97b1a66917fa86a6277c98685a990014408b02cd145030fb61`。

逐文件理由、证据与限制：[计划](quit-without-emptying-plan.md)、[验证记录](../Tests/quit-without-emptying/README.md)。未提交、未推送。
