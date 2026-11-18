# 只读增量复核

独立 reviewer 对比本轮两个源码基线，未将历史未提交修改计入本轮。

- 未发现确定阻断问题。退出 delegate 等待可选任务，MainActor 上释放 terminationTask 后 reply(true)，Cancel 与失败不再否决退出。
- 成功/失败等待期间重复退出仍为 terminateLater，确认与执行各一次；容量刷新完成前不回复。
- Cancel 不执行 Finder、不读取容量、不确认成功清理总量或修改 suppression；关窗未清空仍保持 false 和后台会话。
- 原生夹具提取的生产 delegate 与当前生产源码后缀逐字一致，复用 fixture 的源码哈希一致。
- 红/绿及原生进程日志与要求一致。

局限：原生进程验证为 Cancel 与零清理量场景，AppModel 和更新门禁为 fixture；成功、失败、容量等待与重复请求由真实 AppModel 自检覆盖。未原生验证更新过程和真实 runModal 中的重入。reviewer 未编辑、未调用 Finder、未启动用户真实 App。
