# 维度扫描提示与关闭 Trash 提醒验证

## 现场与失败基线

- 安装版 0.4.26 (140) 中，Project 成功清理的 46.4 MB / 1 项已计入首页；再次关闭确实出现原 Empty Trash / Cancel，已取消，没有执行清空。
- 因此没有声称复现用户当时的具体时序。已在真实红色关闭按钮夹具中复现确定的逻辑缺口：关闭时模型繁忙，稍后成功记账并恢复空闲，原实现丢失提醒。见 [失败日志](trash-red.log)。
- 六模块统一状态入口初始返回 nil，导航回归在 general / waiting 失败，见 [进度失败日志](progress-red.log)。

## 本轮逐文件审查理由

| 文件 | 修改与必要性 |
| --- | --- |
| `Sources/CleanerApp/ModuleProgressView.swift` | 从 AgentEnvironmentProgressView 更名；样式参数全部保留，六页直接复用。旧文件移除，避免两份组件。 |
| `Sources/CleanerApp/AppModel.swift` | 提供按模块状态的文案入口；Agent 扫描文案沿用，准备/覆盖分析分支不变；导航自检覆盖六模块状态和旧报告，防止只看全局任务。 |
| `Sources/CleanerApp/AgentEnvironmentView.swift` | 当前扫描优先于旧结果；原有分析与空列表提示改用共享组件。 |
| `Sources/CleanerApp/CleanupReviewView.swift` | 系统清理扫描时显示共享进度。 |
| `Sources/CleanerApp/ApplicationsView.swift` | 应用卸载扫描时显示共享进度，保留已有首次进入性能优化。 |
| `Sources/CleanerApp/DiskSpaceView.swift` | 大文件原静态图标空态改为同一 spinner，重扫状态优先。 |
| `Sources/CleanerApp/ResourceCleanupView.swift` | Project 和模型分别跟随自己的状态，统一进度样式。 |
| `Sources/CleanerApp/TrashReminderController.swift` | 繁忙时保留一次关闭请求，合并父模型与 Helper 发布；关闭后执行结束用原 dismissDeletionSheet 解除隐藏结果门禁，再调用原接口；主动清空时取消待处理请求，避免重复提示。 |
| `Sources/CleanerApp/TrashReminderWindowObserver.swift` | 关闭事件交给会话 Controller，保留原 NSWindow delegate。 |
| `Sources/CleanerCore/Resources/{en,zh-Hans}.lproj/Localizable.strings` | 两条通用等待/扫描文案，参数与双语同步。 |
| `Tests/exact-trash-dialog/main.swift` | ObservableObject 受控繁忙模型及异步状态回归；fixture 完成后显式退出，避免 AppKit stop 等待新事件造成测试挂起。 |
| `Sources/CleanerApp/TrashEmptyingCheck.swift` | 调用真实 AppModel 门禁回归，保留现有禁止 Finder 的模拟执行器。 |
| `Tests/exact-trash-dialog/check-source.sh` | Observer 入口断言跟随新延迟入口，同时保持最终共用确认及原窗口 delegate 断言。 |
| `Tests/exact-trash-dialog/README.md` | 保留上一版本验证记录，补充本轮繁忙状态回归入口。 |
| `README.md`、`doc/{architecture,development}.md`、`docs/{architecture,development,production-release-checklist}.md` | 更新当前用户行为、架构与验证命令。历史发布说明不重写。 |
| `doc/module-progress-trash-reminder-plan.md` | 保存需求、证据边界、实施与自审；不虚构现场根因。 |
| `Version.json` 与打包生成文件 | 仅由正式构建脚本自动递增，打包后补录实际版本与产物证据。 |

上述增量均服务本轮需求，不撤销之前授权的既有修改。Swift 项目不新增 Python 依赖或 requirements.txt。无根 AGENTS.md 或 .trae/rules/project_rules.md 可更新。

## 已执行

- [导航回归](progress-green.log)：六模块 waiting/scanning、所有终态、缺失状态、重扫旧报告及全局停止。
- [Trash 执行回归](trash-self-check.log)：原两按钮、取消/失败保留、成功确认、互斥与容量等待；无 Finder。
- [原生关闭回归](trash-green.log)：真实红色按钮、原 delegate、延迟记账后只提醒一次、零成功清理不提醒；无 Finder。
- 结果页门禁与 Helper 子模型唤醒分别记录 [sheet 失败](trash-sheet-red.log)、[Helper 失败](trash-helper-red.log)，修复后原生夹具与真实 AppModel 门禁检查通过。
- 只读独立审查发现上述两项边界及旧源码断言，均处理；复核无新增确定问题。未以此宣称已还原用户现场时序。
- 本地化 1268 条双语消息通过源码覆盖和参数校验。

## 正式产物验证

- [正式构建](package.log)：脚本自动递增为 **0.4.27 (141)**；Core contracts 及 **317 项 XCTest / 0 failures** 通过，沿用稳定证书签名。
- [包自检](verification.log)：结构、签名、资源、smoke、导航、权限呈现、Trash 异步门禁等通过；实际 SDK **27.2**、最低 **13.0** 一致。
- [DMG](dmg.log) 与 [产物比对](artifacts.log)：App 与只读挂载 DMG 的版本、严格签名、Apple Events entitlement、三个可执行文件哈希相同。完整值见 [artifact-check.json](artifact-check.json)。
- [原视图比对](style-source-check.log)：共享 View 与 HEAD 中原 Agent View 只有类型名称不同。
- [最终审计](final-audit.log)：生产源码/资源/脚本与构建前快照一致；文档链接、diff 空白和未暂存状态检查。
- 新包位于 `build/SuperCleaner-0.4.27.dmg`，298,984,438 bytes，SHA256 `2f29ccd07eb2d4353a7f36c693f284dfa75b6baa129d419605bbd67fade44a04`。
- `/Applications/SuperCleaner.app` 仍为 **0.4.26**，未强退用户会话、未自动替换安装。新版实际六页视觉及用户当时的具体删除/关闭时序需安装后复测；不将状态自检当成已逐页观察。
- 真实 AppModel 自检新增 receipt 参数初次顺序写错，编译拒绝，已修正并重新构建通过，保留 [首次编译日志](result-gate-check-compile-error.log)。原生夹具异步 stop 等待事件的问题仅改为测试完成显式退出，未改生产生命周期。

没有提交、推送、注册 Helper、扩大权限或调用真实 Finder 清空。

## 自审与建议

- 局部（97/100，已实施）：原 Agent 布局保留为唯一进度组件，避免视觉分叉。
- 全局（94/100，已实施）：待处理关闭请求放入会话 Controller，避免窗口销毁导致丢失。
- 不引入轮询、持久化队列或新的弹窗来源参数；本问题只需一次在内存中的待处理请求。
