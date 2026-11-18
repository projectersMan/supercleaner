# 扫描中可清空 Trash

用户截图证实 0.4.29 在已清理 Project 后显示确认，但 Empty Trash 因 Agent 扫描而禁用。旧版只放开提示，保留执行门禁和 disabled alert 分支，本轮将它们统一删除。

## 逐文件增量理由

| 文件 | 必要修改 |
| --- | --- |
| `Sources/CleanerApp/AppModel.swift` | 合并回单一 canBeginTrashEmptying，移除 !isScanRunning，所有非扫描互斥保留；新增真实模型并发进度检查。 |
| `Sources/CleanerApp/TrashReminderController.swift` | 先资格检查并拿执行锁后才弹确认；删除 allowsEmptying、未拿锁也显示的分支、禁用按钮和等待扫描说明。工厂只保留关闭 checkbox 参数。 |
| `Sources/CleanerApp/TrashEmptyingCheck.swift` | 简化确认依赖，移除固化禁用预期的能力字段，执行新并发回归；其它成功/失败、抑制与退出语义保持。 |
| `Tests/exact-trash-dialog/main.swift` | NSHostingView/真实 Observer 的扫描中关闭场景断言主操作始终 enabled；同步简化回调，保留关闭 checkbox/恢复、原 delegate 和后台会话。 |
| `Tests/exact-trash-dialog/check-source.sh` | 更新单参数工厂断言，禁止残留 allowsEmptying 或 isEnabled 赋值形成禁用分支。 |
| 两份 `Localizable.strings` | 删除已无意义的“等待扫描结束才能清空”说明，保留 1272 条双语完整校验。 |
| README、doc/ 与 docs/ 当前架构、开发和发布检查 | 更新扫描中可执行清空及并发验证边界；历史发布/QA 记录保留。 |
| 本目录、`doc/trash-during-scan-plan.md` | 保存 before 快照、失败/成功日志、逐文件审计和第一性原理反思。 |

未新增依赖；Swift 项目无 requirements.txt/conda。根 AGENTS.md/.trae/rules/project_rules.md 不存在。保留全部历史未提交修改，不提交、不推送。

## 红绿与验证边界

- [模型红灯](red.log)：扫描中清空应可用的断言失败。
- [原生红灯](native-red.log)：实际 NSAlert 的 Empty Trash isEnabled=false，明确失败。
- [模型绿灯](green.log)：关闭/手动×成功/失败，模拟执行挂起时调用真实 receiveModuleScanProgress；验证事件接收、token 不变、扫描不取消、重复执行仅一次、容量刷新及统计/提醒语义。
- [原生绿灯](native-green.log)：NSHostingView+真实 Observer+红色 close，所有显示的确认主操作 enabled，抑制/恢复和后台会话保持。
- [退出](quit-green.log) 与 [来源边界](source-green.log)：明确退出正常结束、不重复提示；关闭独有 checkbox、同一工厂与执行器。
- 并发检查使用真实 AppModel、模拟执行器与合成模块事件，没有运行真实 scanner/Finder。进度/结果/完成回调已只读核对未依赖清空锁；运行时真实 I/O 的各种交错未完整覆盖，不将模拟说成已实机清空。
- 原扫描已排除 Trash 的证据：`DeletedContentScanExclusion` 被大文件索引、扫描和分析复用；本轮未放松候选保护或改变扫描根目录。

## 正式交付

- [正式构建](package.log)：脚本自动升至 **0.4.30 (144)**，Core contracts 与 **318 项 XCTest / 0 failures** 通过。
- [包验证](verification.log)：结构、稳定签名、资源、smoke、导航与 Trash/退出回归通过；SDK **27.2**、最低 **13.0** 保留，1272 条双语校验通过。
- [DMG](dmg.log) 与 [产物比对](artifacts.log)：build 和只读挂载 DMG 内 App 的版本、严格签名、Automation entitlement 与三个可执行文件哈希相同，见 [完整产物值](artifact-check.json)。
- 安装包 `build/SuperCleaner-0.4.30.dmg`，299,014,070 bytes，SHA256 `392ae4dffe146cb2cd99c87e199886f4ff88c198d56915e181b9096c89968e1a`。
- 首次制作 DMG 遇到系统资源忙，见 [初次日志](dmg-initial.log)，不改代码或版本重试后成功；未将失败当通过。
- 未退出、取消或替换正在运行的 **0.4.29**，交付 App/DMG 供安装后测试。不声称旧进程已经运行新逻辑。
- [增量 diff](incremental-diff.log) 已逐文件复核；[独立复核](review.md) 未发现确定问题。源码与构建前快照一致、文档链接/空白检查、HEAD/暂存区和测试生成物清理见 [最终审计](final-audit.log)。
- 没有真实 Finder 清空、权限修改、Helper 注册、提交或推送。测试程序和提取代码清理，保留可重跑脚本和日志。

## 自审

旧“清空仍禁用”的断言把错误设计当作预期，已删除。局部移除能力参数和禁用分支 100/100，全局验证两个入口在挂起执行器下仍能接收扫描进度 96/100，均实施。保留真实操作互斥、用户确认、抑制偏好与失败反馈，不增加队列或扫描暂停。
