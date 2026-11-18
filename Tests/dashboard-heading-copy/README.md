# 清理中心两行说明精简

截图标记的两行文字为标题副说明和 info.circle 扫描范围提示。本批直接删除视图及无用的标题内层 VStack，不隐藏占位；标题下直接显示三张安全卡。没有扫描范围、选择、计时、磁盘空间或清理逻辑变更。

## 逐文件复核

| 文件 | 修改与原因 |
| --- | --- |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 删除指定 Text/Label，标题改为直接 Text，收回对应的布局空间；保持三列公共边界、56pt Scan 按钮和下方六模块布局。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 删除无其它引用的两条消息；双语总计由 1273 降至 1271。 |
| [Version.json](../../Version.json) | 从 0.4.10（124）一次递增为 0.4.11（125），App/Helper 统一。 |
| [README.md](../../README.md) | 更新当前布局和产物入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 标题下直接展示安全卡，不再描述已删除的范围说明。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md) | 同步布局规则及验证记录，保留原有安全与扫描要求。 |
| [实施计划](../../doc/dashboard-heading-copy-plan.md)、本目录 | 记录范围、反思、逐文件理由和验收证据；保留所有前序未提交修改。 |

局部精简评分 100/100，全局文案和文档同步 95/100，均执行，无额外扩展建议。项目为 Swift，无新增依赖，不创建 requirements.txt。根目录无 AGENTS.md 或 .trae/rules/project_rules.md；本次先记录计划再修改。纯文本/结构删除使用既有完整回归与原生视觉检查，不新增复述实现的测试。

## 验证

- [固定证书构建](package.log)：305 项 Release 测试、0 失败，核心契约与 1271 条双语资源检查通过。
- [包验证](verification.log)、[最终 DMG 创建与挂载检查](dmg.log)通过。[首次 DMG 尝试](dmg-attempt-1.log)遇系统资源忙，确认无本批遗留挂载后重试成功，没有修改打包代码或再次递增版本。
- [安装核对](installation.log)确认 App/Helper 同为 0.4.11（125），三个可执行文件与构建一致，严格签名及既有 entitlement 保持一致。
- 安装版原生截图与无障碍树均确认两行小字及占位消失，标题下直接显示三张安全卡，三列操作行、六模块完整可见。最终保持原窗口尺寸、空闲清理中心；没有执行真实清理、清空废纸篓、权限或 Helper 注册。
- [发布记录](../../doc/release-0.4.11.md)同步实际产物。旧安装备份与自检临时 Home 已清理；最终链接、diff 和产物证据见 [最终审计](final-audit.log)。保留前序所有未提交修改，没有提交或推送。
