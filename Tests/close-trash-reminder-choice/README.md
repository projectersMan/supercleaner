# 关闭提醒与不再提醒

## 现场与失败基线

0.4.28 实际会话 Project 已清理 299 MB / 1 项，Agent 仍扫描，首页 Empty Trash 禁用。旧版将提示与清空共用门禁，因此关闭时暂不提示。先前测试把“等全部空闲再提醒”视作正确，遗漏了用户希望在扫描期间直接做提醒选择的场景。

- [扫描中关闭红灯](red.log)：真实 AppModel 失败 `closing after Project cleanup must prompt immediately while unrelated scanning continues`。
- [关闭 checkbox 红灯](native-red.log)：旧工厂没有关闭专用“不再提醒”选项。
- [退出顺序红灯](quit-termination-trace-red.log)：明确退出确认 false → willTerminate → 额外关闭确认 true，证实系统终止时又关窗口造成重入；旧版两个界面相同的测试未在终止通知后发现这次多余确认。

## 逐文件必要修改

| 文件 | 修改与理由 |
| --- | --- |
| `Sources/CleanerApp/AppModel.swift` | 提示资格与实际清空资格分离，只读扫描不再阻塞关闭提醒，永久删除门禁保持；真实模型自检覆盖扫描与偏好。 |
| `Sources/CleanerApp/TrashReminderController.swift` | 单工厂接收清空资格和 checkbox 参数，关闭独有选项；类型化确认同时返回清空意图和抑制选择，抑制不假装清空；终止通知同步屏蔽后续关闭，避免重复；失败文案准确表达未确认成功。 |
| `Sources/CleanerCore/TrashReminderState.swift` | 原偏好 key 公开供设置复用；纯偏好设置替代旧混合 acknowledge，成功计量仍只由 recordTrashEmptied 更新。 |
| `Sources/CleanerApp/PermissionsView.swift` | 同 key 的自动提醒开关让用户恢复“不再提醒”，手动清空始终确认。 |
| `Sources/CleanerApp/TrashEmptyingCheck.swift` | 更新确认依赖，断言扫描中提示/执行资格、关闭抑制持久与恢复、手动不抑制、关闭同意后的成功/失败。 |
| `Tests/CleanerCoreTests/TrashReminderStateTests.swift` | 6 项状态测试，含恢复不丢未清空容量；旧混合 ack 改为成功确认或纯偏好。 |
| `Tests/exact-trash-dialog/main.swift`、`run-native-check.sh` | NSHostingView 的真实 Observer 关闭流程，配置及状态回归；保留只用于人工验证真实 Modal 的 preview，不调用 Finder。 |
| `Tests/exact-trash-dialog/check-source.sh` | 旧“绝不允许 checkbox”的断言按新需求改为关闭独有选项、仍只有同一工厂和执行器。 |
| `Tests/quit-without-emptying/main.swift` | 终止通知日志即时写出，以捕获随后多余关闭确认；明确退出仍只有一次确认。 |
| `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings` | 新增关闭选项、扫描说明、设置文案，修正 4 条失败信息；1273 条双语完整校验。 |
| README、doc/ 与 docs/ 当前架构、开发、发布检查 | 说明新旧需求变更、扫描提示与执行分离、偏好恢复和退出去重；历史发布记录保留。 |

生产增量对照本目录 before 快照；保留全部历史未提交修改，不提交、不推送。无新依赖，Swift 项目无需 requirements.txt/conda；根 AGENTS.md 和 .trae/rules/project_rules.md 不存在。

## 自动验证与边界

- [真实模型回归](green.log)：扫描中立即提示且不放行清空，关闭同意成功/失败复用执行器，偏好持久/恢复、手动确认和明确退出均通过。
- [原生关闭](native-green.log)：实际 NSHostingView + Observer + 红色 close；原工厂配置包含关闭 checkbox、扫描说明和禁用清空，抑制及恢复通过。
- [真实进程退出](quit-green.log)：有清理仅确认一次、无清理不确认；终止后不再出现额外关闭提示。
- [源码边界](source-green.log) 与 [6 项状态测试](state-tests.log)；原生调用均使用禁止 Finder 的执行器。
- 实际 Modal 人工预览尝试未形成通过证据：原生控制服务返回 timeoutReached / ScreenCaptureKit -3811，未能读取并操作独立测试弹窗。预览只涉及隔离 domain，已停止测试进程，未改用户真实偏好，未清空 Trash。配置/状态测试不冒充已人工点选生产弹窗。
- 独立复核发现退出重入和失败文案不尊重 suppression，两项均修复并重跑；复核无新增确定问题。
- 只读检查现有 `cleanup.suppressTrashReminder` 为 0，见 [偏好记录](live-preference-read.log)，排除了历史抑制设置。历史旧夹具在本轮之前已不兼容当前接口，不改写历史素材，也不作为当前通过证据。

## 正式交付

- [正式构建](package.log)：脚本自动升为 **0.4.29 (143)**，Core contracts 与 **318 项 XCTest / 0 failures** 通过。
- [包内验证](verification.log)：结构、稳定签名、资源、smoke、导航、状态与 Trash 回归通过；SDK **27.2**、最低 **13.0** 一致。
- [DMG](dmg.log) 与 [产物核对](artifacts.log)：build 与只读挂载 DMG 内的版本、严格签名、Automation entitlement、三个可执行文件哈希一致，见 [artifact-check.json](artifact-check.json)。
- 安装包 `build/SuperCleaner-0.4.29.dmg`，299,005,288 bytes，SHA256 `5a4982f5290d2faa3699f451035e920e07989bc9c2a7115c61782be28dbc527a`。
- 为保留用户正在运行的扫描，未关闭或替换当前 **0.4.28** 安装；本轮交付已编译验签的 App/DMG，需安装新版后测试新选项。不将尚未安装的新版说成当前运行版。
- [增量 diff](incremental-diff.log) 按文件复核；源码/资源/构建脚本与构建前快照一致，文档链接、diff 空白、HEAD/暂存区及生成物清理见 [最终审计](final-audit.log)。
- 无提交、推送、系统权限变更、Helper 注册、真实清理或 Finder 清空。独立测试程序生成物清理，人工 preview 入口保留为可复现素材，不计为已通过 UI 验证。

## 自审

- 局部（98/100，已执行）：提示与永久删除的资格必须分离，扫描继续；禁用清空时明确说明，不排队执行。
- 全局（94/100，已执行）：单工厂/执行器、可恢复的同 key 偏好、真实终止通知去重，避免 UI 来源和生命周期分叉。
- 不把“不再提醒”视为成功清空，不以通过受控夹具推断已还原用户全部实机场景。
