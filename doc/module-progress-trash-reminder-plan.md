# 维度扫描提示与关闭提醒实施计划

> **For agentic workers:** 使用 superpowers:executing-plans 在当前工作区按任务实施；保留已有修改，不提交、不推送。

**Goal:** 六个维度页统一采用 Agent 的扫描提示；窗口关闭时因清理收尾繁忙而未能展示的 Trash 提醒不能丢失。

**Architecture:** 原有进度视图更名为共享组件，AppModel 根据各模块实际 waiting/scanning 状态提供文案。Trash Controller 保留一次待处理的关闭请求，监听原模型状态，空闲后调用已有 requestEmptyTrash，不复制弹窗、不轮询、不替换窗口 delegate。

**Tech Stack:** Swift 6、SwiftUI、AppKit、Combine；不新增依赖。

**Spec:** 本轮用户关于六维度扫描提示、Project 删除后关闭未提醒的反馈。

## 约束与证据

- macOS 最低 13，SDK 记录保持实际编译值；继续同一个会话模型与原生窗口。
- 当前安装版 0.4.26 (140)，实际界面显示 Project 成功清理 46.4 MB / 1 项；再次关闭能出现标准两按钮弹窗，已取消，无清空操作。
- 当前 canBeginTrashEmptying 在清理执行、结果 sheet、扫描及其它互斥流程中为 false；willClose 只调用一次 remindIfNeeded，繁忙时直接返回，没有后续处理。先用受控繁忙状态复现这个漏提醒分支，不能声称已证明用户当时的具体时序。
- 不修改历史 suppression 偏好；取消/失败不能确认清理总量；任何测试禁止执行 Finder 或真实废纸篓删除。

## Review Focus

- 单模块已完成而其它模块仍扫描：显示结果，不显示转圈。
- 重扫有旧结果、等待状态、取消/失败、全扫描停止：提示严格匹配当前模块状态。
- Agent 列表准备与覆盖分析提示：复用组件后保持。
- 关闭时本轮清理尚未记账或结果 sheet 尚在：状态恢复后提醒一次；零成功清理不提醒。
- 重复 close、取消提醒、主动 Empty Trash、成功/失败：不产生重入或重复提醒，不影响原窗口 delegate。

## Task 1：共享维度进度

- [x] 在 AppModel 导航自检中加入六模块 waiting/scanning/terminal、旧结果重扫、无关模块完成断言，先运行确认失败。
- [x] 将 AgentEnvironmentProgressView 更名为 ModuleProgressView，保持全部布局参数；六页在扫描状态优先展示它。
- [x] 提供统一中英文等待/扫描文案；保留 Agent 特有提示与分析阶段。
- [x] 运行导航自检；原共享视图与 HEAD 逐字比较（仅类型改名），现场确认旧版关闭使用原弹窗。新版六页视觉复测留给安装包测试，不声称已在安装版逐页观察。

## Task 2：关闭请求不丢失

- [x] 在 Tests/exact-trash-dialog 的真实红色关闭按钮夹具中加入繁忙/记账延后场景，先运行确认当前版本失败。
- [x] Controller 接收关闭请求并在模型空闲后重试一次，Observer 调用此入口；执行及确认仍只使用 requestEmptyTrash。
- [x] 验证零清理、重复关闭、取消、主动按钮、原 delegate；禁止真实清空。

独立审查补充：已关闭窗口的完成结果 sheet 仍会阻塞门禁；仅在关闭请求内调用原 dismissDeletionSheet，执行中其 guard 继续保护。Helper 为独立 ObservableObject，合并其发布以保证门禁解除后唤醒。这两个场景分别先记录失败，再修复通过；另补真实 AppModel 的执行期/结果期门禁自检。

## Task 3：交付

- [x] 检查每处 diff，更新 README、doc/ 与 docs/ 当前说明；逐文件理由与验证存入 Tests/module-progress-trash-reminder。
- [x] 正式编译一次，由脚本自动递增版本；验签、制作 DMG、比对 App 与只读挂载 DMG 内的三个可执行文件。按用户本轮“编译打包我测试”的交付范围提供安装包，保留正在使用的旧版会话，不强退或自动替换。
- [x] HEAD 与暂存区保持原样，不提交、不推送。

## 第一性原理自审

- 局部：复用一个进度 View，消除六页样式分叉，97 分，执行。
- 全局：把延迟提醒保留在会话级 Controller，不绑定已关闭视图生命周期，94 分，执行。
- 不增加另一种确认框或定时轮询：这些不能修复请求丢失且引入状态分叉，不实施。
