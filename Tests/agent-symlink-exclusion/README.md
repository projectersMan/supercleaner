# Skill/MCP软链接定向验证

生产检查源码：[AgentSymlinkExclusionTests.swift](../CleanerCoreTests/AgentSymlinkExclusionTests.swift)。使用LocalFileSystem在本目录fixtures下创建真实文件和软链接，单项结束后删除临时目录，不操作用户Agent资源。

运行用户已授权的检查：

```sh
swift test --disable-sandbox --cache-path .build/release-cache --scratch-path .build/release-scratch --configuration release --filter 'AgentSymlinkExclusionTests|AgentScannerTests'
```

2026-11-02：12项通过（新增4项、现有AgentScanner 8项），无失败。修复前新增3项产生13个断言失败；新增的真实对象恢复检查复现缺失关系，修正后通过。编译仅显示既有ApplicationUpdateModel.swift弱引用捕获警告。

覆盖范围：目录链接、manifest文件链接、MCP文件链接、父目录链接、断链均不进入清单；真实目标独立保留，真实Skill内无关的引用链接不导致整项消失。旧缓存链接不生成新配对、不提供覆盖或预选；真实对象再次出现时复用已有向量补齐关系。未运行全量测试，未执行清理。
