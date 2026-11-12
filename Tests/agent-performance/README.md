# Agent 性能探针

`Profile.swift` 提供真实目录扫描及隔离索引迁移核对。使用当前 debug CleanerCore 编译后运行，不连接 MCP，不执行清理。

```sh
swift build
xcrun swiftc -parse-as-library -I .build/arm64-apple-macosx/debug/Modules -I Sources/CleanerZIP Tests/agent-performance/Profile.swift .build/arm64-apple-macosx/debug/CleanerCore.build/*.o -o /tmp/supercleaner-agent-profile -framework Security -framework SystemConfiguration -lz
/tmp/supercleaner-agent-profile scan
```

存储模式需要先手动创建隔离空目录（例如 `mktemp -d /tmp/agent-profile.XXXXXX`），再把返回路径传入：

```sh
/tmp/supercleaner-agent-profile storage /tmp/agent-profile.EXAMPLE
/tmp/supercleaner-agent-profile replay /tmp/agent-profile.EXAMPLE
/tmp/supercleaner-agent-profile matrix /tmp/agent-profile.EXAMPLE
/tmp/supercleaner-agent-profile commit /tmp/agent-profile.EXAMPLE
```

`storage` 直接解码真实旧格式摘要并读取旧向量，不通过可能自动迁移真实索引的 `load` 入口。新文件仅写入指定隔离目录；完成后断言双向位图、联合覆盖和排名一致。`replay` 加载新格式副本并测量向量和排名读取（旧分区信封会自动迁移，仅作用于指定隔离目录）。`matrix` 使用已有向量重算所有同类关系，按对象 ID 对齐两个方向核对，并保存 matrix-result.plist 供诊断。`commit` 核对未变化提交不改分区，并在隔离副本中改变一个标题，断言只改写该对象及引用该标题的推荐来源。

存储模式针对 v3 legacy 摘要；真实索引已迁移为新格式时请改用隔离副本 replay 或旧摘要副本，不要将格式解码失败当作性能回归。所有模式都不应把真实用户索引路径作为隔离输出目录。
