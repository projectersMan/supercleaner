# 独立只读复核

review_trash_exit_reuse 检查本轮统一 controller、delegate、关闭观察器、状态和隔离测试：未发现重要缺陷。成功前保持 busy 门禁；失败不确认会话容量；显式跳过不运行执行器；首按钮均不会触发永久删除；退出复用一个任务与一次 reply。

初次复核指出，注入 reply 的自检未覆盖 AppKit 的实际 terminateLater 运行循环。为此补 check-appkit-termination.py：逐字复制生产 delegate，用模拟清空依赖在原生 RunLoop 事件中触发退出，实际 NSApplication 等待异步依赖并正常退出，日志 appkit-native.log。

初版 probe 用 Task 触发 NSApp.terminate，自造主队列递归排空问题而超时；阶段跟踪定位在 Task 创建后无法启动清空任务，改用原生 RunLoop 事件后通过，生产代码未为此改动。初始调试记录保留，不把该 harness 超时误报为生产清空失败。模拟依赖不调用 Finder，真实控制器的操作/容量等待另由正式包隔离自检覆盖。
