# 0.4.27 (141)

- 六个清理维度页统一复用 Agent 原有扫描提示；仅本模块等待/扫描时显示，重扫有旧报告同样适用，完成模块可正常查看。
- 窗口关闭时的 Trash 提醒不再因清理收尾暂时繁忙而直接丢失；会话 Controller 保留一次请求，执行结束后解除隐藏结果页门禁，并跟随 Helper 发布唤醒。
- 确认仍调用原 Empty Trash 接口、原两按钮弹窗；取消/失败不确认清理量，执行期间保持保护，恢复记录与统计保留。

正式构建自动升版；317 项 XCTest、Core contracts、包自检与稳定签名通过。App 与挂载 DMG 的版本、entitlement 和三个可执行文件哈希一致。SDK 27.2 / 最低 macOS 13.0。

安装包：[SuperCleaner-0.4.27.dmg](../build/SuperCleaner-0.4.27.dmg)。SHA256：`2f29ccd07eb2d4353a7f36c693f284dfa75b6baa129d419605bbd67fade44a04`。

本轮编译打包供用户测试，未自动替换仍为 0.4.26 的现有安装，未强退会话。未提交、未推送、未清空真实废纸篓。

实现与逐文件理由：[实施计划](module-progress-trash-reminder-plan.md)、[验证记录](../Tests/module-progress-trash-reminder/README.md)、[独立审查](../Tests/module-progress-trash-reminder/review.md)。没有声称重现用户当时的具体时序；已确定复现并修复繁忙分支丢失、结果门禁与 Helper 唤醒这三种路径。
