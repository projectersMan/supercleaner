# 废纸篓确认完全一致回归

0.4.30 起每个显示的确认框 Empty Trash 都必须 enabled；只读扫描不阻塞清空，不再保留 allowsEmptying 参数或扫描等待说明。当前并发行为与证据见 [扫描中清空](../trash-during-scan/README.md)，下文 0.4.29 的禁用预期为历史行为。

0.4.29 按新需求允许关闭提醒显示“不再提醒”，手动及明确退出不显示；下面无 checkbox 的条目是历史版本证据。当前夹具已用 NSHostingView 包住真实 Observer，并覆盖扫描不停、checkbox 持久化/恢复与退出去重，见 [当前验证](../close-trash-reminder-choice/README.md)。`--modal-preview` 是只写隔离偏好且执行器禁止调用的人工 UI 验证入口，不属于自动通过证据。

0.4.28 修正明确退出时的 Cancel：保留垃圾箱并完全退出；它与红色关窗后继续后台运行的语义独立。下面的 0.4.26 历史说明中“取消退出返回 false”已被替代，现行源码自检与真实 NSApplication 退出证据见 [自主退出回归](../quit-without-emptying/README.md)。确认框仍只有原两个按钮。

0.4.27 在保持下面 0.4.26 确认语义的基础上，增加繁忙时关闭不丢提醒的回归。最新日志见 [本轮验证](../module-progress-trash-reminder/README.md)：受控模型现在包含完成结果 sheet 与独立 Helper 发布；真实红色按钮验证延迟记账、重复关闭只提醒一次、零成功清理不提醒、Helper 单独完成能唤醒。`check-source.sh` 跟随新的 `remindAfterWindowClose` 入口；最终仍调用同一个 `requestEmptyTrash`。测试不调用 Finder。

本批只修改下面四个已有源码文件；它们还包含主任务此前未提交的修改，未重置或覆盖这些修改。

| 文件 | 本批修改与必要性 |
| --- | --- |
| [TrashReminderController.swift](../../Sources/CleanerApp/TrashReminderController.swift) | 删除 `TrashEmptyingContext`、`TrashEmptyingDecision`、跳过清空和新增抑制偏好的分支；确认依赖收敛为无参数 Bool。唯一 `makeEmptyingAlert()` 负责固定标题、说明、Cancel / Empty Trash 两个按钮及安全默认键；`confirmEmptying()` 只运行该确认。`FinderTrashEmptying` 的脚本、命令、完成验证未改。 |
| [TrashReminderWindowObserver.swift](../../Sources/CleanerApp/TrashReminderWindowObserver.swift) | 调用无来源参数的同一提醒入口，并明确关闭阶段的 Cancel 仅取消清空。继续只观察对应窗口 willClose，保留 SwiftUI delegate、窗口生命周期及会话模型。 |
| [CleanerApp.swift](../../Sources/CleanerApp/CleanerApp.swift) | 仅把退出提醒调用改成无来源参数，原 `terminateLater` / `Task<Bool, Never>` 结果等待、容量刷新和退出门禁保留。 |
| [TrashEmptyingCheck.swift](../../Sources/CleanerApp/TrashEmptyingCheck.swift) | 删除旧上下文、跳过和不再提醒的模拟接口，使用与生产一致的 Bool 确认；补充取消退出返回 false、关闭取消保留提醒、0 字节、既有抑制偏好仍禁止提醒。成功/失败、重复调用、容量刷新挂起、成功关闭后不再提示的回归保持。 |
| [本批计划](../../doc/exact-trash-dialog-plan.md)、本目录 | 记录计划、边界、逐文件审计与隔离回归。复用既有中英文文案，无新增依赖、配置或资源。 |

## 已运行

- [源码红灯](source-red.log)：同一个 request 入口仍按来源调整界面并暴露额外选项，明确失败。
- [源码绿灯](source-green.log)：`zsh Tests/exact-trash-dialog/check-source.sh` 通过。它仅验证源代码统一入口和删除界面分叉，**不代替运行时或视觉验证**。
- `zsh -n Tests/exact-trash-dialog/check-source.sh Tests/exact-trash-dialog/run-native-check.sh` 语法检查通过。
- `git diff --check` 通过；已逐处阅读四个源文件的 `git diff`，本批改动均为删除界面分叉或同步调用/回归所必需。
- [原生首次断言日志](native-initial-assertion.log)：旧测试要求 Cancel 的 `keyEquivalent` 恒为 Escape；AppKit 设置该按钮为 `defaultButtonCell` 后会归一化为 Return，因此此断言错误。已删除该不可靠断言，继续按按钮 cell 身份验证安全默认按钮，生产代码未改。
- [原生重跑日志](native.log)：实际红色 close、0 字节、首页/关闭同一 factory 及两按钮、无 suppression、其他面板、原 delegate 和会话模型保留、Cancel 后后台提醒均通过。构建输出仅写本目录的独立夹具，不修改主构建产物。

## 复现命令

```bash
swift build --product CleanerApp
$(swift build --show-bin-path)/CleanerApp --trash-emptying-self-check
zsh Tests/exact-trash-dialog/run-native-check.sh
```

[原生夹具](main.swift)与生产 Controller / Observer 一同编译，仅注入最小 AppModel、取消确认及禁止调用的清空执行器。实际点击主窗口的标准红色 close 按钮，检查：0 字节不提示；首页 request 与 close 调用同一个生产 NSAlert factory，标题和正文相同、只有 Cancel / Empty Trash、无 suppression；其他面板关闭不提示；原 NSWindow delegate 与同一模型保留；Cancel 不清空、不刷新容量、不记为已完成，窗口仍关闭、应用与提醒留在后台。它不会调用 Finder，也不访问真实废纸篓。

原生夹具自动读取 factory 配置并取消，不进行真实清空；独立验证 `NSApplication` 明确退出的异步 reply 由既有 `--trash-emptying-self-check` 覆盖。主任务统一编译及正式注入自检已通过；本子任务随后获准单独构建运行本目录原生夹具，日志见上。

## 复核

删除多余上下文比继续维护三种文案更符合“完全相同弹窗”的请求。保留 willClose 的生命周期语义可继续保持关闭后扫描会话；把 Cancel 改成重建窗口会引入更大的行为变化，因此未作此修改。

局部统一确认与删除跳过路径 100/100；全局保留清空成功、容量刷新和退出等待的一致链路 98/100；真实红色 close 隔离回归 96/100，均已实施。无额外功能建议。本批未提交或推送。
