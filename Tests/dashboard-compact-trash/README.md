# 单页清理中心、废纸篓操作与资源页统一验证

本批基于已交付但尚未提交的 0.4.4（118）继续修改，保留上一批全部六维度实现；目标版本一次递增到 0.4.5（119），不因追加排版要求或重试构建再次递增。计划见 [dashboard-compact-trash-plan.md](../../doc/dashboard-compact-trash-plan.md)。没有提交或推送。

## 已授权行为与自我复核

首页移除外层上下滚动，扫描及下方计时、紧凑容量、累计清理及清空按钮同行等高；六个模块和底部安全卡保留。资源页采用与应用/大文件一致的搜索、范围、排序和全宽分组，详情按需展开，默认仍不勾选。

清空按钮先明确确认永久删除，再异步请求 Finder；不会遍历或直接 rm 用户 Trash。Finder 返回成功且已空才确认操作启动时的累计字节，原有“不再提醒”偏好保持不变；失败/取消/超时保留提醒，新清理可以再提醒。操作结束刷新真实卷容量，忙碌状态同时约束按钮、模型执行入口和退出。

自我批评重点：不能仅隐藏滚动条却裁切内容；不能为了缩小页面删入口；不能用清空命令的零退出码冒充实际已空；不能在确认前执行、失败后免提醒或把期间新增清理也确认掉；分组勾选不能绕过受保护/占用/不完整候选，筛选不能取消其它维度的选择。

联动审查实际发现两项并修复：旧 AppModel 候选全集漏了模型/项目，导致其它模块回执后丢选、永久保护不立即撤选；页面私有筛选与底栏隐藏选中数/焦点脱节。现补齐候选全集并保留同路径别名，两页筛选按 destination 保存在 AppModel，候选、焦点、底栏统一使用 `visibleCandidates`。实际编排回归先检出 9 项失败，再全部通过，未执行真实清理。

局部建议：最小窗口完整可见 99、确认后才显示清空中 95、只确认成功时的启动基线 100、过滤后分组选择安全 100；全局建议：复用同一提醒状态 100、Finder 负责系统废纸篓语义 97、统一资源页操作且复用原执行链 98，均纳入本批实施。无额外依赖或未授权功能。

## 验证证据

完整 Release XCTest **300 项、0 失败**，核心契约全部通过，1248 条双语消息检查通过，见 [构建日志](package.log)。[完整包验证](verification.log) 通过签名、实际 Automation entitlement、中英用途描述、macOS 13 最低版本、偏好、烟雾及全部内部自检。[DMG 验证](dmg.log) 通过生成、挂载、Applications 拖拽入口、图标和包签名。

[安装校验](installation.log) 确认 App/Helper 都是 0.4.5（119），三个可执行文件与构建副本 SHA256 相同；主 App 仅签入必要 Automation entitlement，独立 CLI 仍不在包内。旧版空闲后正常退出再替换 `/Applications/SuperCleaner.app`，未替换应用数据或偏好目录；旧安装备份和测试夹具已清理。

原生界面已核验默认窗口和系统四分之一窗口动作允许的最小窗口：首页三个区域等高、六行导航与底部安全卡全部可见，无外层上下滚动；扫描中用时在按钮下，底栏出现后仍可见。模型/项目页在窄窗口下过滤栏自动分两行，全宽分组、展开/收起、真实路径、占用保护及按需详情符合参考页布局。模型搜索 whisper 得到 1/4 项，可清理范围显示 0/4；项目页保持独立空搜索及 9/9 项。真实可见项全选、切换保护范围后底栏显示 1 项被隐藏、清空选择均符合预期，未点击“确认删除”。

清空流程的测试全部使用假执行器；实机确认了永久删除文案，并点击取消返回首页，没有执行真实用户废纸篓清空或授予 Automation 权限。只读扫描用于发布两资源页的实际清单，没有等待全部后台模块结束；结束检查后正常退出停止扫描，再重新打开空闲首页，临时勾选及筛选已清除。英语界面实测，中文资源和包内语言检查通过，未改用户语言设置。

独立审查确认两项选择/筛选贯通缺口均已修复；最后只读复跑最新导航自检通过。没有在代码冻结后改动生产源码或再次递增版本。

[最终审计](final-audit.log) 确认本地文档链接无新增失效、`git diff --check` 通过、临时夹具与旧安装备份已清理；保留历史缺失的 0.2.25 生成镜像链接，不改写历史交付记录。

- [提醒状态红灯](state-red.log)、[状态绿灯](state-xctest.log)：新增会话确认接口，确认基线、新清理量与持久 suppress 偏好分离。
- [编排红灯](controller-red.log)、[编排绿灯](controller-green.log)：确认取消零执行；成功、失败、取消、超时、拒绝权限、未确认结果；重复请求、非空选择门禁、操作中新增清理及结束后的容量刷新。自检不调用 Finder。
- [资源策略红灯](resource-policy-red.log)、[策略绿灯](resource-policy-green.log)：3 项筛选、排序与安全组选择回归。
- [实际 AppModel 红灯](resource-integration-red.log)、[贯通绿灯](resource-integration-green.log)：回执、永久保护、独立筛选、焦点、底栏隐藏数和可见项批量操作；沿现有导航自检运行。

## 按文件说明必要性

| 文件 | 本批修改与原因 |
| --- | --- |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 移除外层滚动，三块同行等高，计时放按钮下；压缩六行和安全卡；提示替换为共享控制器按钮。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 统一搜索、范围、排序、计数、全宽可折叠分组及按需详情；避免大检查器挤压列表，复用安全选择入口。 |
| [ResourceCleanupListPolicy.swift](../../Sources/CleanerCore/ResourceCleanupListPolicy.swift) | 集中可见项筛选/排序与可清理项边界，便于真正验证组选择不绕过保护。 |
| [ResourceCleanupListPolicyTests.swift](../CleanerCoreTests/ResourceCleanupListPolicyTests.swift) | 验证筛选、排序、选择保留、占用/不完整/保护项和手动 review 资格。 |
| [ResourceCleanupPresentationFixture.swift](../../Sources/CleanerApp/ResourceCleanupPresentationFixture.swift) | 只读合成两个资源维度与其他候选，使 AppModel 回执、保护和底栏测试经过实际编排。 |
| [TrashReminderController.swift](../../Sources/CleanerApp/TrashReminderController.swift) | 同一会话状态承担显式确认、异步有界 Finder 调用、已空证明、错误反馈与免提醒基线。 |
| [TrashReminderState.swift](../../Sources/CleanerCore/TrashReminderState.swift) | 增加只更新会话基线的成功清空接口，不写 suppress 偏好。 |
| [TrashReminderStateTests.swift](../CleanerCoreTests/TrashReminderStateTests.swift) | 两项新增回归证明旧基线不回退、新清理可提醒、持久偏好不变。 |
| [TrashEmptyingCheck.swift](../../Sources/CleanerApp/TrashEmptyingCheck.swift) | 用受控 continuation 和假容量读取验证编排，避免真实永久删除；沿用现有包内自检模式。 |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 废纸篓忙碌门禁贯通执行/恢复/维护/扫描/更新；完成后确保新容量读取。补齐两资源候选全集，按页保存筛选，统一可见项/焦点/隐藏计数，并用实际编排回归。 |
| [CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 环境注入同一个提醒控制器；忙碌退出取消；包内安全自检入口。 |
| [ContentView.swift](../../Sources/CleanerApp/ContentView.swift) | 清空期间禁用相关界面与底栏，与模型硬门禁一致。 |
| [AppInfo.plist](../../Resources/AppInfo.plist) | 声明仅确认后请求 Finder 清空的 Apple Events 用途。 |
| [en InfoPlist.strings](../../Resources/en.lproj/InfoPlist.strings) | 英语 Automation 用途说明。 |
| [zh-Hans InfoPlist.strings](../../Resources/zh-Hans.lproj/InfoPlist.strings) | 中文 Automation 用途说明。 |
| [App.entitlements](../../Resources/App.entitlements) | 仅新增正式 Hardened Runtime 所需 Apple Events Automation 权限，不加入其它放宽项。 |
| [build-app.sh](../../Scripts/build-app.sh) | 主 App 签名附加必要 entitlement，既有 Helper/更新/发布门禁保留。 |
| [verify-app.sh](../../Scripts/verify-app.sh) | 检查实际签入的 Automation 权限、中英用途说明并运行无删除自检。 |
| [en Localizable.strings](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 英语按钮、确认、错误与资源筛选文案。 |
| [zh-Hans Localizable.strings](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 中文同键与占位符，保留上一批全部资源。 |
| [Version.json](../../Version.json) | 本批只递增一次至 0.4.5（119）。 |
| [README.md](../../README.md) | 更新单页、废纸篓联动和资源操作说明，修正导航与计时位置，移除过期首页截图。 |
| [doc/architecture.md](../../doc/architecture.md) | 更新布局边界、同一会话状态与异步系统操作架构。 |
| [doc/development.md](../../doc/development.md) | 明确最小窗口、无真实删除验证、并发门禁与安全选择要求。 |
| [docs/architecture.md](../../docs/architecture.md) | 同步详细架构，替换常驻检查器描述。 |
| [docs/development.md](../../docs/development.md) | 同步实现/验证约定、用途描述与签名要求。 |
| [docs/production-release-checklist.md](../../docs/production-release-checklist.md) | 增加单页、资源页、成功才免提醒和签入权限验收项。 |
| [实施计划](../../doc/dashboard-compact-trash-plan.md) 与本目录 | 记录合并后的三项授权、先计划后修改、红绿与最终证据，保留清晰审计边界。 |
| [release-0.4.5.md](../../doc/release-0.4.5.md) | 记录本批实际版本、测试、原生核验、镜像及安装事实与验证界限。 |

项目为 Swift，无新增 Python 包与 requirements.txt。根目录仍无 AGENTS.md 和 .trae/rules/project_rules.md，未凭空创建。生成物继续位于忽略的 build 目录；中间夹具、二进制与旧安装备份在交付前清理。
