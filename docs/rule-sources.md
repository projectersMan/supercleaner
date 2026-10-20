# Rule Source Ledger

本台账用于证明清理规则的独立来源和验证责任。它不记录、复制或改写 Mole 的源码、Shell 脚本、文案、UI、图标或规则实现。

卸载所有权图补齐（2026-10-15）：应用组共享语义依据 [Apple App Groups Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups)；Cask 管理与 zap 区别依据 [Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook) 和 [brew manpage](https://docs.brew.sh/Manpage)。实现不运行卸载或 zap，不复制第三方清理规则。安装收据采用本机 `pkgutil --help` 所描述的只读收据/BOM 语义，直接解析元数据并使用受限 lsbom 验证精确载荷路径；临时 mkbom 夹具验证包标识符不相似时仍能关联正确路径。独立契约见 `ApplicationOwnershipContract.swift`，责任模块 App Uninstall。

| Reference | Source kind | Fact used | Independent validation | Owner |
|---|---|---|---|---|
| `SRC-APPLE-CACHE-001` | Platform convention | 当前用户的 `~/Library/Caches` 是应用缓存容器；目录本体仅凭年龄仍需确认 | macOS 实机只读枚举；`ScannerTests.old-cache`；路径与符号链接契约 | Core Engine |
| `SRC-AGENT-SANDBOX-001` | Independent observation | Agent Provider 的已完成任务沙箱可能包含可重建构建缓存；Skills、配置、凭证和会话不等同缓存 | 自建 fixture；`AgentScannerTests`；知识资产永不 safe 契约 | Agent Engine |
| `SRC-APP-BUNDLE-001` | Platform convention | 应用由 `.app` Bundle 与 Bundle ID 标识，关联项必须进行完整边界匹配 | Foundation Bundle 元数据；prefix-collision 契约；共享数据保护契约 | App Uninstall |
| `SRC-GIT-WORKTREE-001` | Tool semantics | 无法证明干净、已合并、未锁定、未使用的 worktree 不可安全删除 | 保守策略始终 blocked；无 Shell 调用；Agent contract | Agent Engine |
| `SRC-CODEX-RESOURCE-PATHS-001` | OpenAI official docs/source | Codex MCP 使用用户/项目 `config.toml`；Skills 使用 `.agents/skills`，并兼容 `.codex/skills` 与管理员目录 | `docs/research/agent-mcp-skill-paths.md`；`AgentResourcePathRegistry`；Agent contract | Agent Engine |
| `SRC-CLAUDE-RESOURCE-PATHS-001` | Anthropic official docs | Claude MCP 使用 `~/.claude.json`、项目 `.mcp.json` 与 managed MCP；Skills 覆盖个人、项目、同步、插件和管理员位置 | `docs/research/agent-mcp-skill-paths.md`；`AgentResourcePathRegistry`；Agent contract | Agent Engine |

新增规则必须分配稳定 reference，记录观察设备/系统版本、验证日期、测试夹具和再生成依据。来自第三方清理产品的实现、表达、路径清单或规则结构不得进入本台账。

2026-10-15 独立实现批次（macOS 本机 + 临时目录夹具；契约 `RuleEngineContract`、`InstallerDiscoveryContract`）：

| Reference | 来源与使用事实 | 决策与独立验证 | Owner |
|---|---|---|---|
| `SRC-APPLE-LOG-001` | 用户 Logs/DiagnosticReports/CrashReporter 约定；只发现明确日志/诊断扩展名 | 人工选择，目录本体不删除；递归有预算 | Core Engine |
| `SRC-NPM-CACHE-001` | [npm 官方缓存设计](https://docs.npmjs.com/cli/v11/commands/npm-cache/)：`_cacache` 是可重新获取的缓存，不是持久数据 | 精确缓存根、活动 node/npm 检查、最新内容年龄、敏感文件检查 | Core Engine |
| `SRC-PYTHON-CACHE-001` | [pip 官方缓存文档](https://pip.pypa.io/en/stable/topics/caching/)：macOS 默认缓存位置和缓存用途 | 不假设内部版本目录固定；工具活动阻止清理 | Core Engine |
| `SRC-UV-CACHE-001` | [uv 官方缓存安全](https://docs.astral.sh/uv/concepts/cache/)明确禁止直接修改缓存 | `.cache/uv` 仅发现，始终 blocked；不经隔离移动 | Core Engine |
| `SRC-XCODE-DERIVED-001` | [Apple 构建输出文档](https://developer.apple.com/documentation/xcode/distributing-documentation-to-other-developers)说明 DerivedData 存放构建输出；默认目录为平台约定 | 自建目录夹具，Xcode/xcodebuild/swift/clang 活动阻止清理 | Core Engine |
| `SRC-GRADLE-CACHE-001` | [Gradle 官方目录布局](https://docs.gradle.org/current/userguide/gradle_directories.html)：缓存与 daemon 目录和用户配置分离 | 仅精确产物目录；不触及 properties、init.d、wrapper 与 jdks | Core Engine |
| `SRC-PACKAGE-CACHE-001` | 现有独立扫描器的包缓存目录约定 | 仅人工选择；活动工具检测；不承诺离线依赖可用性 | Core Engine |
| `SRC-XCODE-STATE-001` | Archives、Simulator、DeviceSupport 是开发状态，不能仅凭名称推断可丢弃 | 默认保留；禁止归入自动清理 | Core Engine |
| `SRC-APPLE-FIRMWARE-001` | 现有独立固件扫描器的精确下载缓存位置 | 只识别 ipsw，默认保留；活动 Configurator 阻止清理 | Core Engine |
| `SRC-INSTALLER-DISCOVERY-001` | 独立下载来源约定及系统 zipinfo/unzip 归档检查 | 嵌套目录、包目录、损坏 ZIP、普通 ZIP、根链接与后代链接夹具；不复制第三方清理产品路径表 | Core Engine |
| `SRC-PROJECT-ARTIFACT-001` | 项目 manifest 与对应依赖/构建目录惯例；Git `ls-files` 的跟踪索引 | 独立临时仓库夹具：五类目录、跟踪文件、嵌套 `.git`、部署密钥、活动状态、外部链接、隔离和恢复；`ProjectArtifactContract` | Project Cleanup |
| `SRC-GO-BUILD-CACHE-001` | [Go 官方命令文档](https://go.dev/cmd/go/)与[官方缓存实现](https://go.dev/src/cmd/go/internal/cache/default.go)：macOS 标准用户缓存下的 `go-build` 保存可重建构建产物 | 仅精确默认根；Go/gopls/编译器活动时阻止；40 天临时夹具验证精确规则覆盖宽泛缓存发现 | Core Engine |
| `SRC-DENO-CACHE-001` | [Deno 官方安装文档](https://docs.deno.com/runtime/getting_started/installation/)：macOS 默认 `DENO_DIR` 为 `~/Library/Caches/deno`，官方提供 `deno clean` | 依赖缓存支持离线工作，保持 review 且不默认选择；Deno 活动时阻止 | Core Engine |
| `SRC-CARGO-CACHE-001` | [Cargo Home 官方文档](https://doc.rust-lang.org/cargo/guide/cargo-home.html)：`registry/cache` 保存下载的 crate 归档，可重新下载 | 规则根仅覆盖精确下载缓存，不包含凭证、配置和已安装二进制；离线构建风险使其保持 review | Core Engine |
| `SRC-COCOAPODS-CACHE-001` | [CocoaPods 官方命令参考](https://guides.cocoapods.org/terminal/commands.html)：`pod cache clean` 支持按 Pod 或全部清理 | 精确用户缓存根、pod/ruby 活动检查；私有源和离线依赖使其保持 review | Core Engine |
| `SRC-PLAYWRIGHT-BROWSERS-001` | [Playwright 官方浏览器文档](https://playwright.dev/docs/browsers)：macOS 浏览器二进制位于 `~/Library/Caches/ms-playwright`，可由 CLI 安装/卸载 | 保持 review；保护同根下 `daemon` 持久会话和浏览器状态；Node/浏览器活动时阻止 | Core Engine |
