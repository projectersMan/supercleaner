# 保留 Trash 并直接退出实施计划

> **For agentic workers:** 在当前工作区按 superpowers:executing-plans 实施；保留已有修改，不提交、不推送。

**Goal:** 用户明确退出 App 时，可在原 Empty Trash 弹窗中选择 Cancel，保留垃圾箱并完全退出。

**Architecture:** 原 Controller 的 Bool 只表示清空是否成功，不能作为退出权限。退出 delegate 等待已有可选清空任务结束后批准退出；确认 UI、Finder 执行器、关闭窗口保留会话的逻辑继续复用。

**Tech Stack:** Swift 6、AppKit、SwiftUI；无新增依赖。

**Spec:** 本轮用户明确要求“用户有权利选择不清理直接退出”。

## 证据与范围

- requestTermination 目前将 await emptying.value 原样传入 reply；Cancel 与失败都返回 false，导致无法正常退出。
- 单独点击 Empty Trash：Cancel 只取消清空，App 继续运行。
- 红色关闭：只关闭窗口，App 与扫描在后台继续；Cancel 只取消清空。
- 明确退出：Cancel 不调用 Finder，直接退出；选择清空则等待其执行、容量刷新与必要错误说明结束后退出，清空失败也不强迫用户留下。
- 既有更新、正在执行清空的并发退出门禁保持；不增加退出专用弹窗或第三个按钮。

## Review Focus

- Cancel 后真实 NSApplication 完全终止，不重复提醒或清空。
- 选择清空时不提前退出，成功/失败均等待操作与容量刷新。
- 取消不确认清理总量、不改变 suppression 偏好、不执行 Finder。
- 红色关闭与单独 Empty Trash 的 Cancel 仍保留后台会话。
- 重复退出请求不重复确认，不破坏已有更新门禁。

## 实施

- [x] 先调整真实 delegate 的自检，记录 Cancel 退出预期失败；增加隔离 NSApplication 退出夹具，禁止 Finder。
- [x] 仅在退出 delegate 解耦清空结果与退出许可；原窗口关闭及 Controller 保持。
- [x] 运行退出、窗口关闭与已有 Trash 执行回归；逐文件审查差异并更新当前文档。
- [x] 正式脚本自动升版至 0.4.28 (142)，构建、验签并打包；317 项测试及包内自检通过。旧版已退出后安装新版，比对 build/安装/挂载 DMG 三份产物并打开主窗口；不提交、不推送。

## 自审

- 局部：退出意图与清空结果必须独立，100/100，实施；不靠更改 Cancel 文案或另造弹窗掩盖问题。
- 全局：用真实 NSApplication 的退出通知和进程结束验证，96/100，实施，补上先前只验证 Bool 回调的不足。
- 本轮不改扫描或窗口生命周期；Swift 项目无需 requirements.txt 或 conda。根 AGENTS.md 与 .trae/rules/project_rules.md 当前不存在。
