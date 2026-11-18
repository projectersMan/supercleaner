# 保留 Trash 并完全退出

用户明确要求“用户有权利选择不清理直接退出”。旧版把清空任务的 Bool 作为退出许可，导致 Cancel 或失败均无法退出。现修复为清空可选，明确退出的意图独立。

## 行为

| 入口与选择 | 结果 |
| --- | --- |
| 首页 Empty Trash → Cancel | 不清空，App 继续运行。 |
| 红色关闭 → Cancel | 不清空，只关闭窗口，扫描与会话仍在后台。 |
| 菜单退出/Cmd+Q → Cancel | 不清空，完全退出。 |
| 明确退出 → Empty Trash | 等待清空任务、容量刷新及必要错误提示结束，然后退出；失败也允许退出。 |

原弹窗与两个按钮、Finder 实现、历史 suppression 偏好、清空成功才确认清理总量、并发/更新门禁均保持。

## 逐文件增量审查

| 文件 | 必要修改与理由 |
| --- | --- |
| `Sources/CleanerApp/CleanerApp.swift` | 唯一生产行为修改：等待可选任务后 reply(true)，不把未清空误判为撤销退出；先清 terminationTask 再回复，保留去重与等待。 |
| `Sources/CleanerApp/TrashEmptyingCheck.swift` | Cancel 回归先运行；成功/失败结束与容量刷新后都允许退出，重复请求仍只确认/执行一次，红色关窗未清空仍返回 false。 |
| `Tests/quit-without-emptying/main.swift` | 实际 NSApplication 终止、willTerminate 通知、一次确认、无清空/容量/统计改动断言；超时明确失败，不用回调值冒充实际退出。 |
| `Tests/quit-without-emptying/run-native-check.sh` | 从生产源码原样提取 delegate，复用已有 Cancel-only 模型及 probe，编译真实 Controller/Observer；不手写另一套退出逻辑。源码哈希留存，生成素材全部放 Tests。 |
| `Tests/quit-without-emptying/install-and-check.py` | 复用已有安装比对脚本，在旧版进程已结束时替换安装，比对三个可执行文件及签名/权限；不强制退出、不更改系统权限。 |
| README、doc/ 与 docs/ 当前架构/开发/检查清单 | 清除“Cancel 撤销退出”的现行说明，记录用户自主决定和验证命令。历史发布说明保留。 |
| `doc/exact-trash-dialog-plan.md`、`Tests/exact-trash-dialog/README.md` | 标明先前退出语义已修正，统一弹窗与关窗后台语义仍保留。 |
| `doc/quit-without-emptying-plan.md`、本目录 | 保存计划、基线、逐文件理由和验证。 |
| `Version.json` 与打包生成产物 | 正式构建脚本自动升版，不手动递增；打包完成后补录证据。 |

源码增量基线：[CleanerApp](before-CleanerApp.swift.txt)、[Trash 自检](before-TrashEmptyingCheck.swift.txt)。其它未提交修改均保留，不重置、不暂存、不提交、不推送。Swift 项目不新增 requirements.txt；无 Python 第三方依赖。根 AGENTS.md 与 .trae/rules/project_rules.md 不存在。

## 已验证

- [红灯](red.log)：真实 delegate 自检明确失败 `Cancel must preserve Trash and allow explicit application termination`。
- [原生红灯](native-red.log)：真实 NSApplication.terminate 后 Cancel 仍留下进程，3 秒超时明确失败。
- [绿灯](green.log)：真实 AppModel/Controller/delegate 自检，Cancel/成功/失败/容量等待/重复请求均通过。
- [原生绿灯](native-green.log)：有成功清理时只确认一次并终止进程；无清理量时零确认并终止；执行器禁止调用 Finder，无读容量或更改清理统计。
- [窗口关闭回归](close-green.log) 与 [共享来源断言](source-green.log)：原八项红色关闭行为及共享确认通过。
- 独立只读复核未发现确定阻断问题；原样提取 delegate 和复用 fixture 的哈希一致。原生进程检查覆盖 Cancel/零清理量；成功/失败/重复退出由真实模型自检覆盖。未原生验证更新过程或真实 runModal 中的重入。

## 交付验证

- [正式构建](package.log)：自动升版 **0.4.28 (142)**，Core contracts 与 **317 项 XCTest / 0 failures** 通过。
- [包内验证](verification.log)：结构、稳定签名、资源、smoke、导航及 Trash 执行/退出回归全部通过。实际 SDK **27.2**、最低 macOS **13.0** 一致；1268 条双语校验通过。
- [DMG](dmg.log)、[安装比对](installation.log)、[完整产物值](artifact-check.json)：build、`/Applications/SuperCleaner.app`、只读挂载 DMG 内 App 的版本、严格签名、Apple Events entitlement 与三个可执行文件哈希相同。
- DMG：`build/SuperCleaner-0.4.28.dmg`，298,984,334 bytes，SHA256 `356b7e7d83534c97b1a66917fa86a6277c98685a990014408b02cd145030fb61`。
- 原安装版 **0.4.27 (141)** 的进程已结束后才替换；未强退。已通过原生工具打开新安装版，主窗口正常、初始清理量为 0，未发起真实删除或清空。原生正清理量 Cancel 退出证据来自禁止 Finder 的隔离夹具，不冒充实机删除验证。
- [增量 diff](incremental-diff.log) 已按文件逐处审查，唯一生产行为变更在退出 delegate；[独立复核](review.md) 无确定阻断问题。生产源码与构建前快照一致，文档链接、diff 空白、HEAD 和暂存区检查见 [最终审计](final-audit.log)。
- 清理测试生成的 App、提取代码与安装备份，保留可复现脚本、原始基线及验证日志；没有提交、推送、Helper 注册或真实 Finder 调用。

## 反思与建议

先前只考虑了统一确认框，却错误地把“未清空”与“用户不再想退出”绑定；测试也把这个错误当成预期。现按用户决定修正退出边界，同时用真实进程结束证据验证。

- 局部解耦可选清空结果与退出许可：100/100，已实施。
- 全局补真实 NSApplication 终止回归：96/100，已实施。
- 不新增第三个按钮、弹窗上下文或配置项；用户通过现有 Cancel 即可保留 Trash 并退出。
