# 清理后关闭提醒验收与逐文件复核

## 结果

已实现：本次累计清理量大于 0 时，关闭主窗口或直接退出应用会提醒；同一累计容量确认后不重复，新增清理后可再次提醒。“不再提醒”保存在 UserDefaults，跨进程生效。

根据用户对实机弹窗的反馈，正文已精简为：**本次已清理 {0}，清空废纸篓以释放空间。** 保留“打开废纸篓”“直接关闭/继续退出”和“不再提醒”。数字仍为本次已清理量，不将恢复区保留量冒充废纸篓可释放空间。

## 验证证据

- [red.log](red.log)：新增状态测试首次失败，原因是缺少 TrashReminderState。
- [targeted.log](targeted.log)：容量边界、同容量去重/新增清理、偏好重新加载，3 项通过。
- [suite.log](suite.log)：完整 `swift test`，264 项、0 失败。
- [contracts.log](contracts.log)：`swift run CoreContractChecks` 通过。
- [preferences.log](preferences.log)：两个独立进程分别写入、读取提醒偏好；第二个进程确认对任意正容量仍不提醒，并删除测试偏好域。
- [native-ui.log](native-ui.log)：原生夹具通过 0 字节、其他面板、正容量关闭、同容量重开/退出、新增清理与持久抑制检查。使用弹窗获得焦点事件计数，关键阶段分别为 0、1、1、2、2；不能仅以 runModal 返回后 modalWindow 为 nil 判断未曾弹窗。
- CUA 实际看到精简中文弹窗、勾选“不再提醒”后的选中状态和最终 PASS 窗口；“打开废纸篓”进入 Finder 的废纸篓窗口，未执行清空。
- [package.log](package.log)：固定签名构建 0.4.3（117），包括 release XCTest 264 项通过、核心契约、CLI 与 Helper 打包门禁。
- [package-verification.log](package-verification.log)：App 结构、签名、双语、版本、隔离/恢复烟雾测试及既有应用自检通过。
- [dmg.log](dmg.log)：DMG 生成、挂载、签名与拖拽入口检查通过。
- `python3 Scripts/check-localizations.py`：1191 条双语文案、参数与源码覆盖通过；`git diff --check` 通过。

现有 ApplicationUpdateModel.swift 的 2 处强弱引用捕获编译警告仍存在；DMG 工具提示 hdiutil 部分选项被弃用，命令成功。本次没有修改这些既有逻辑。

## 复核与修正

独立审查未发现可确认的生产代码缺陷，指出原生夹具可能把“重复弹出后被关闭”误判为“不曾弹出”。已增加弹窗实际出现计数、正向次数和抑制偏好断言，并重新完成原生交互，最终 PASS。另补充有效按钮响应检查，系统中断 modal 时不写入已确认容量或关闭提醒偏好。

原生夹具使用仅持有 CleanupSessionSummary 的替身 AppModel，以避免扫描和真实清理副作用；它验证实际 controller 和 NSView 关闭观察器，不把该夹具解释为真实清理或完整 SwiftUI/更新退出端到端测试。真实安装副本已正常启动；退出门禁接入通过代码复核及应用构建验证。最小化不发关闭通知，由观察的通知类型保证，未把程序化最小化动画作为验证证据。

## 逐文件必要性

仅记录本次增量。开始工作时仓库已有卸载资格等未提交修改，均保留，不计入本次实现。

| 文件 | 本次修改与必要性 |
| --- | --- |
| [TrashReminderState.swift](../../Sources/CleanerCore/TrashReminderState.swift) | 集中判断正容量、已确认容量与永久关闭偏好；两个关闭入口得到相同判断。 |
| [TrashReminderController.swift](../../Sources/CleanerApp/TrashReminderController.swift) | 原生精简提醒、偏好保存和 Finder 废纸篓入口；打开失败可见，中断不算确认，弹窗期间防重入。 |
| [TrashReminderWindowObserver.swift](../../Sources/CleanerApp/TrashReminderWindowObserver.swift) | 仅观察实际挂载的主窗口，移动窗口时重新绑定；保留 SwiftUI 自身 delegate，其他面板不触发。 |
| [CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 主窗口挂载观察器，delegate 弱引用共享 AppModel；直接退出通过原更新门禁后复用同一提醒实例。 |
| [en Localizable.strings](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 新增对应英文提醒、按钮、勾选和打开失败文案，保持占位符一致。 |
| [zh-Hans Localizable.strings](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 添加中文文案，并根据用户反馈将长说明改为一句。 |
| [TrashReminderStateTests.swift](../CleanerCoreTests/TrashReminderStateTests.swift) | 检验 0、1、最大字节、容量确认、新增清理与偏好重新加载。 |
| [main.swift](main.swift) | 原生关闭交互夹具；用真实弹窗计数捕捉多弹、漏弹及错误抑制。 |
| [Info.plist](Info.plist) | 给 UI 夹具独立应用身份，隔离正式应用偏好并支持 LaunchServices 正常启动。 |
| [build-ui-check.sh](build-ui-check.sh) | 将已验证的原生夹具编译/资源组装命令保存为可重复步骤；不添加依赖。 |
| [preferences.swift](preferences.swift) | 独立进程验证真实 UserDefaults 持久化，测试数据使用独立域并清理。 |
| [Version.json](../../Version.json) | 本批在既有 0.4.2（116）基础上递增一次为 0.4.3（117），使 App、Helper 与 DMG 对应。 |
| [README.md](../../README.md) | 更新用户可见的关闭提醒行为与最新本地产物入口。 |
| [doc/architecture.md](../../doc/architecture.md) | 记录状态、原生提醒、窗口观察和退出接入的职责，更新当前包版本。 |
| [doc/development.md](../../doc/development.md) | 记录提醒资格、通知边界、偏好键及回归命令；依赖仍为现有 SwiftPM。 |
| [docs/architecture.md](../../docs/architecture.md) | 同步原架构入口中的关闭/重开生命周期，避免两套文档相互矛盾。 |
| [docs/development.md](../../docs/development.md) | 同步原开发入口中的关闭提醒约束与验收路径。 |
| [trash-close-reminder-plan.md](../../doc/trash-close-reminder-plan.md) | 保存先计划后修改的范围、决策、执行状态和用户的精简文案反馈。 |
| [release-0.4.3.md](../../doc/release-0.4.3.md) | 保存 App、DMG、签名和固定安装路径的交付结果。 |
| 本目录验证日志 | 保留红绿测试、完整回归、跨进程、原生交互和打包证据；清除临时 app、二进制、旧安装备份和采样文件。 |

逐处检查确认上述修改均服务于提醒、准确展示、持久偏好或验证；未扩大扫描或删除范围。项目为 Swift，没有 Python 运行依赖，不创建无用途的 requirements.txt。根目录 AGENTS.md 与 .trae/rules/project_rules.md 不存在，不新增规则文件。

## 可重复验证

```sh
swift test --filter TrashReminderStateTests
zsh Tests/trash-close-reminder/build-ui-check.sh
open Tests/trash-close-reminder/TrashReminderHarness.app
```

第一张弹窗选择“打开废纸篓”（回车）；第二张出现新增容量后勾选“不再提醒”，按 Escape 直接关闭。最终窗口标题显示 PASS，日志写入本目录。按日志动作操作即可，测试期间不要反复切换同一弹窗焦点，因为夹具按获得焦点事件计数。夹具不扫描、不移动或清空用户文件。

跨进程验证：

```sh
swiftc -swift-version 6 -parse-as-library Sources/CleanerCore/TrashReminderState.swift Tests/trash-close-reminder/preferences.swift -o Tests/trash-close-reminder/preferences-check
Tests/trash-close-reminder/preferences-check write SuperCleaner.TrashReminderProcessCheck.Manual
Tests/trash-close-reminder/preferences-check read SuperCleaner.TrashReminderProcessCheck.Manual
```

## 第一性原理建议及执行

- 局部，100 分：用户只需要知道本次已清理容量与下一步操作，因此正文精简为一句，已执行并在中文界面验证。
- 全局，95 分：窗口关闭与退出是同一提醒决策的两个入口，应共享容量确认和偏好状态；已执行并验证相同容量不会重复提醒。

本轮建议均达到 85 分并已实施，没有待批准的扩展项。未执行 git commit 或 push。
