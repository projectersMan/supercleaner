# 项目扫描目录设置验证

目标：Settings 提供多个项目扫描目录的草稿编辑；默认可见三行，更多目录在内部滚动。不是只保留/扫描前三项，不增加全盘或 Git 发现策略。

## 逐文件复核

| 文件 | 修改与必要性 |
| --- | --- |
| [PermissionsView.swift](../../Sources/CleanerApp/PermissionsView.swift) | 设置增加项目扫描目录；44pt 行、132pt 内部视口保留完整列表。原生面板支持多选，草稿逐项移除、统一保存/撤销，路径可复制/悬浮查看，失败可重读。避免每次删行就扫描。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 复用原 ProjectScanRootsStore，公开加载/保存状态及错误；设置无报告只保存，已有报告只刷新项目，项目页原首次扫描继续权限准备。范围变更后取消刷新不能执行旧项目结果；保存期间禁止新扫描、权限继续、模块续跑、清理及清空入口。自检验证同一模型门禁，不执行清理。 |
| [CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 既有包自检串入新配置回归，不增加用户 CLI。 |
| [ContentView.swift](../../Sources/CleanerApp/ContentView.swift) | 目录读写期间同时禁用内容与底部操作栏，避免侧栏切换后续跑旧配置扫描。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 目录错误在无报告时也可见；取消刷新后提示重新扫描，不改变手动选择和保护规则。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 14 条新消息双语配对，含计数、保存、撤销及错误。 |
| [Version.json](../../Version.json) | 从 0.4.9（123）一次递增 0.4.10（124），不因重建重复递增。 |
| [README.md](../../README.md) | 用户配置入口、三行滚动、保存与移除语义及当前产物。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 记录单一存储、草稿、首次保存与项目单模块刷新。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 记录回归范围、旧范围与续跑门禁、无报告错误展示。 |
| [实施计划](../../doc/project-scan-roots-settings-plan.md)、本目录 | 保留方案反思、评分和真实验证证据；沿用原工作区、保留既有未提交改动。 |

项目为 Swift，无新增依赖，不新增 requirements.txt 或 conda 环境。根目录无 AGENTS.md、CONTEXT.md 或 .trae/rules/project_rules.md。局部三行滚动 98、添加/移除/保存 100，全局共用存储与安全门禁 100，均已实施；没有额外扩展建议。

## 回归与审查

- [首次红灯](red.log)：新增 API 前自检无法编译；[并发门禁红灯](busy-red.log)：目录操作未阻止 Trash 入口；[绿灯](green.log)：修复后通过。
- 独立只读审查发现取消模块续跑遗漏保存门禁、首次无报告时项目页隐藏错误两项问题。[审查回归红灯](review-red.log)确认新扫描/权限继续/续跑门禁缺失，[审查回归绿灯](review-green.log)确认修复。复审未发现新增问题。
- 假 Home 自检覆盖完整默认列表、多目录去重及持久化/重开、空列表保留为空、无报告设置不扫描、拒绝根目录不覆盖旧配置、真实写入失败显式错误且不启动权限、项目单独刷新、取消后旧范围不可执行、损坏配置不默默回填默认值。所有测试写入均在本目录临时夹具内。

## 最终验收

- [固定证书完整构建](package.log)：305 项 Release 测试、0 失败，核心契约和 1273 条双语资源检查通过。
- [包自检](verification.log)、[DMG创建/挂载/签名检查](dmg.log)、[安装核对](installation.log)通过。App/Helper 均为 0.4.10（124）；三个可执行文件及严格签名、既有 entitlement 与构建一致。
- 原生普通窗口确认默认三行，滚动条移到末尾可查看 .codex/.claude/.worktrees，设置外层位置不变。草稿移除后 11→10，Save/Discard 可用，点击 Discard 恢复 11 且两按钮重新禁用。
- 原生面板同时选择 Alpha/Beta 两个本批空目录后草稿 11→13，撤销回 11；取消面板也保持 11，Save/Discard 仍禁用。期间工具短暂失联，采样见 [诊断摘要](panel-timeout.log)与[进程采样](panel-timeout.sample.txt)：主线程正常空闲、CPU 0%；经 Finder 重开窗口后恢复，确认多选已完成，未对无证据的卡死假设修改代码。
- 系统 Top Left 窄窗口下，设置外层滚动至配置区后，内部保持三行，路径、Remove 和 Add/Save/Discard 均完整可见。使用 Return to Previous Size 恢复原窗口，关闭本批打开的 Finder 窗口，最终安装版留在空闲清理中心。
- [真实配置前状态](user-config-before.json)与[后状态](user-config-after.json)一致，文件均不存在，未保存测试草稿到用户 Home；没有执行清理、清空废纸篓、权限或 Helper 注册。

临时测试 Home、面板空目录与旧安装备份已清理；最终逐文件 diff、文档链接和产物一致性见 [最终审计](final-audit.log)。保留所有前序未提交修改，没有提交或推送。
