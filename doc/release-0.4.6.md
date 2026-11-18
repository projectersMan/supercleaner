# 0.4.6（120）本地交付

按用户截图移除清理中心顶部扫描、磁盘容量、累计清理三个区域的容器底色与圆角框。仅删除 DashboardView.hero 的共有背景修饰器，保留同行等高布局、计时、按钮和容量刷新行为。

[Version.json](../Version.json) 从 0.4.5（119）递增一次。固定证书构建完成，300 项测试、0 失败，核心契约与 1248 条双语检查通过；完整包验证及 DMG 挂载/签名检查通过，见 [逐文件审计与验证日志](../Tests/dashboard-plain-summary/README.md)。

[SuperCleaner.app](../build/SuperCleaner.app) 与 [SuperCleaner-0.4.6.dmg](../build/SuperCleaner-0.4.6.dmg) 已更新。安装副本 `/Applications/SuperCleaner.app` 已重新打开并原生确认顶部无底色和外框；App/Helper 版本、严格签名、Automation entitlement 与三个可执行文件一致，见 [安装日志](../Tests/dashboard-plain-summary/installation.log)。

应用数据和偏好目录保留，未实际清空废纸篓、授予系统权限、提交或推送。本地证书与包检查不代表 Developer ID、公证或线上发布验收。
