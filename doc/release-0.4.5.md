# 0.4.5（119）本地交付

本批合并用户三项要求：

- 清理中心压缩为单页；扫描按钮及下方计时、紧凑卷容量、累计清理和清空按钮同行等高，六行导航与底部安全卡完整可见。
- 累计清理下方提供“清空废纸篓”。用户确认后由 Finder 执行，成功才确认启动时的累计清理量；结束刷新磁盘容量。取消/失败保留退出提醒，后续新清理可再次提醒，原有“不再提醒”偏好不变。
- 本地 AI 模型和项目产物页统一采用应用/大文件的搜索、范围、排序、全宽可折叠分组、三态勾选与按需详情，继续默认零预选并保护占用或未完整核验项。

同时修复候选全集遗漏导致跨模块回执丢选、保护不立即撤选，以及页面筛选与底栏隐藏数/焦点脱节；实际 AppModel 回归已接入原导航自检。

[Version.json](../Version.json) 从 0.4.4（118）递增一次，App/Helper 同为 0.4.5（119）。完整 Release 测试 300 项、0 失败，核心契约与 1248 条双语检查通过，见 [构建日志](../Tests/dashboard-compact-trash/package.log)。[完整包验证](../Tests/dashboard-compact-trash/verification.log) 与 [DMG 挂载/签名检查](../Tests/dashboard-compact-trash/dmg.log) 通过。

[SuperCleaner.app](../build/SuperCleaner.app) 使用既有固定证书签名；[SuperCleaner-0.4.5.dmg](../build/SuperCleaner-0.4.5.dmg) 已生成。安装副本 `/Applications/SuperCleaner.app` 已替换并重新打开，版本、签名、Automation entitlement 和三个可执行文件与构建一致，见 [安装日志](../Tests/dashboard-compact-trash/installation.log)。未替换应用数据或偏好目录。

默认/系统最小可用窗口、扫描态、资源搜索/分组/保护/按需详情、可见项全选和隐藏计数已原生验证。仅临时勾选并清除，不执行删除；清空确认只走取消，成功/失败等编排由假执行器验证。实机检查后正常退出只读扫描并重开空闲首页；未实际清空废纸篓、授予 Automation 权限、注册 Helper、提交或推送。

逐文件原因、红绿证据、复核评分及界限见 [验证审计](../Tests/dashboard-compact-trash/README.md)。本地证书及包检查不代表 Developer ID、公证或线上发布验收。
