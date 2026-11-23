# Helper 生命周期与卡顿排查

Helper 只处理已授权的受限应用本体、安装收据等文件操作。扫描、普通页面展示和应用激活不发送特权文件操作。当前没有现场证据将偶发切回转圈归因于 Helper，不能将闲置采样或注入测试当作事发复现。

## 职责与边界

| 模块 | 职责 |
| --- | --- |
| [HelperSettingsModel](../Sources/CleanerApp/HelperSettingsModel.swift) | 合并状态刷新，显式安装/移除/注册，验证连接并持有授权会话。 |
| [HelperClient](../Sources/CleanerCore/HelperClient.swift) | SMAppService 注册状态与有限 XPC 操作；仅 ping/perform 创建连接。 |
| [HelperSecurity](../Sources/CleanerCore/HelperSecurity.swift) | 双方身份与签名检查、管理员会话；每次实际操作仍验证系统授权。 |
| [HelperProtocol](../Sources/CleanerCore/HelperProtocol.swift)、[HelperService](../Sources/CleanerHelper/HelperService.swift) | v3 握手，校验连接 UID、短期令牌及操作摘要。 |
| [HelperFileOperations](../Sources/CleanerCore/HelperFileOperations.swift) | 限定路径、身份、链接、条目和时限，不覆盖目标。 |
| [CleanupExecutor](../Sources/CleanerCore/Execution.swift) | 日志、恢复及不确定结果对账；超时不盲目重试已经发出的修改。 |

授权复用至进程退出、主动撤销或系统校验失效，不能使用旧的“五分钟”描述。注册、连接和会话授权分开；被动刷新不能自动提权。开发签名不能通过正式 Helper 身份门禁，SMAppService 的 notFound 也不能单独证明包内文件缺失。

## 激活和潜在等待

[AppModel.applicationDidBecomeActive](../Sources/CleanerApp/AppModel.swift) 保留运行应用和必要权限刷新，已移除容量读取；容量仍在启动、扫描、清理、恢复及清空后的既有生命周期更新。侧栏只显示当前容量，不记录启动以来的变化基准。

Helper 注册状态读取已在后台并合并请求，但已授权分支仍可能在 MainActor 调用系统授权检查或等待其锁。显式安装/升级路径也包含同步签名及系统注册工作。这些是条件性风险，尚未证明是用户偶发转圈的原因。`--activation-self-check` 只覆盖注入慢读取与请求合并，不能替代真实授权、锁竞争和整页绘制测试。

## 现场诊断

卡顿发生时记录当前页面、是否启用 Helper 和是否已经授权，再只读采样主线程。使用系统命令即可，无需保留独立状态探针或包装脚本：

```sh
mkdir -p Tests/temporary
pgrep -f '^/Applications/SuperCleaner[.]app/Contents/MacOS/CleanerApp([[:space:]]|$)'
# 将上条命令确认的唯一进程号填入 PID
sample PID 5 1 -file Tests/temporary/cleaner-stall.sample
```

检查主线程是否停在 Authorization/Security、SwiftUI/AttributeGraph、文件系统或普通事件等待。独立进程查询 SMAppService 绑定的是其调用方 bundle，不能代替安装版完整激活测试。采样不注册服务、不申请管理员权限、不执行文件修改。
