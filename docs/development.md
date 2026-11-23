# 开发与验证

使用 macOS 13 及以上、Swift 6；完整 XCTest 需要 Xcode。当前架构和业务规则只在 [架构文档](architecture.md) 维护，旧版计划、专项日志及发布事实见 [历史归档](history.md)。

## 资源与构建

模型由 Git LFS 管理。首次克隆或机器未配置 LFS 时，先取回实际资源，134 字节指针不能用于编译：

```sh
git lfs install --local
git lfs pull --include='Sources/AgentOverlapAI/Resources/Models/embeddinggemma-2-Q8_0.gguf'
./Scripts/build-app.sh
```

构建脚本校验模型大小及 SHA-256、双语资源，编译推理运行时和主应用，运行 CoreContractChecks 与 Release XCTest，组装 App/Helper/Sparkle 后由内到外签名。常规运行会一次性递增 [Version.json](../Version.json) 的 patch/build；基础预检失败不写入，已开始编译的失败不回滚号码。

明确发行版本使用 `./Scripts/build-app.sh --version <更高版本>`；测试、独立验证和生成 DMG 不递增版本。重新编译需要清理两个 Swift 编译目录时，使用：

```sh
swift package --scratch-path .build/release-scratch clean
swift package --package-path AgentInference --scratch-path .build/agent-inference clean
```

本地构建默认使用临时签名（ad-hoc），不需要开发者证书或私钥，可在多台 Mac 上直接编译打包。即使本机存在以前固定的证书，默认也不会自动选择它。覆盖更新可能需要重新授予完全磁盘访问等权限，属于已接受的本地开发行为。启动、返回应用及扫描入口会检查权限；明确访问被拒绝时重新显示授权流程，不能绕过为受限扫描。扫描中确认权限失效会停止本轮并保留已有结果，授权并重开后重新扫描。无法确认与明确拒绝分开处理，单个应用目录受限不直接判定为完全磁盘访问失效。

构建、应用自检、独立运行检查和 DMG 打包采用相同默认策略。临时签名也必须通过签名完整性和包内资源检查；此设置不放宽正式发布的 Developer ID、公证和生产配置门禁。

固定证书签名是可选模式：显式设置 `SUPERCLEANER_REQUIRE_STABLE_SIGNING=1`，并通过 `SUPERCLEANER_SIGN_IDENTITY` 或 `SUPERCLEANER_SIGN_IDENTITY_FILE` 指定身份。缺少指定证书或私钥时严格模式停止，不改选身份；也可使用本机 `~/Library/Application Support/SuperCleaner/Signing/identity.sha1`。私钥不进入 Git、App 或 DMG。详见 [生产发布清单](production-release-checklist.md)。

## 验证入口

```sh
python3 Scripts/check-localizations.py
python3 Scripts/check-doc-links.py
python3 -m unittest discover -s Tests -p 'test_*.py'
swift test --disable-sandbox --cache-path .build/release-cache \
  --scratch-path .build/release-scratch --configuration release
./Scripts/verify-app.sh
```

`verify-app.sh` 验证包结构、模型及许可证、App/Helper 版本、SDK/最低系统、签名完整性、两种语言及扫描、清理、导航、权限、应用响应和 Trash 自检。

打包后还须运行 `zsh Scripts/verify-standalone.sh`：暂时移开 `.build` 并在退出时恢复，验证 App 不依赖编译目录；支持的平台额外用包内模型和运行时产生真实 embedding。

可独立运行 `swift run CoreContractChecks`，或针对 `--check-core-read-only`、`--check-review-coverage`、`--check-ownership`、`--check-updates` 运行契约。打包规则验证使用 `--check-packaged-rule-config /绝对路径/SuperCleaner.app`，不依赖已退役的 CLI。

原生 AppKit 检查统一为：

```sh
zsh Tests/NativeChecks/run-checks.sh
```

默认验证 Trash 确认、取消退出和真实 AppKit 异步退出循环；不调用 Finder 删除用户内容。`icons` 依赖本机 WorkBuddy，缺少返回 77，不能计为通过；`agent` 需要构建后的真实模型运行时；`signing` 需要可用固定证书。源码、入口和性能探针说明见 [测试索引](../Tests/README.md)。

## 打包与产物复核

```sh
version=$(python3 Scripts/version.py resolve | head -n 1)
./Scripts/create-dmg.sh "$PWD/build/SuperCleaner.app" "$PWD/build/SuperCleaner-$version.dmg"
python3 Scripts/check-artifacts.py
```

DMG 输出必须是新路径。已有包需要重做时先移到临时备份，不用生成过程覆盖未知文件。创建脚本验证 App、Applications 快捷方式、图标及镜像内签名；统一产物检查还会验证镜像校验和，只读挂载后逐文件比较应用目录、权限、内容与链接，检查 App/Helper/Version.json 一致，最后卸载并输出 JSON 与 SHA-256。

`check-artifacts.py --installed-app /Applications/SuperCleaner.app` 只比较现有安装副本，不替换或启动。是否安装必须来自当前任务授权；不能把历史安装记录当作当前包的验证。

## 修改边界与回归要求

- 总计划必须验证推荐与手动同时存在、只有手选、应用卸载、模型共享、跨维度父子去重、取消选择、保护和配置过期。统计和执行必须共用同一集合；局部筛选不能缩小首页总计划。
- 项目预选测试覆盖未配置默认开启、显式关闭持久化、人工取消保留、当前结果即时更新和扫描/执行期间的门禁。根目录保护须覆盖不可见子项，立即撤销勾选并持久化。
- 不用测试镜像或用户真实文件执行清理回归。使用独立临时目录、合成回执和假 Finder 执行器；原生检查只验证取消和受控执行器。
- 修改窗口/退出时覆盖红色关闭、最小化重开、Dock 重开、重复终止与异步等待；不能替换 SwiftUI 窗口 delegate。
- 修改卸载时保留归属、共享、系统、运行状态和实时身份复验；保留件或未知验证失败不能获得移动权限。
- 删除结果优先展示失败和跳过项，成功项放在后面；两组内部保留原有顺序。文件与安装收据采用同一展示规则，原始执行回执和恢复记录不重排。
- 修改发布时检查正式身份、Runtime、时间戳、生产配置、签名 feed 和公证；本地阳性自检不能代替真实特权连接、真实升级及干净 Mac 验收。

## 工作区与文档维护

可运行 XCTest 位于 `Tests/CleanerCoreTests` 和 `Tests/CleanerAppTests`，版本脚本测试保留在 `Tests/test_version.py`。所有探针输出、截图、日志、一次性脚本和夹具统一写入被忽略的 `Tests/temporary/`；Swift 产物在 `.build/`，当前 App/DMG 在 `build/`。清理缓存前确认构建与核验已完成，保留当前交付物。

不再新增逐版本的重复 architecture/development 文件，也不为同一次校验复制安装或产物脚本。历史追溯使用 [归档](history.md) 或 Git 历史；持续使用的检查迁入统一入口，保留真实回归源码。更新文档后运行链接检查。

设置页按项目扫描、大文件、删除与恢复、永久保护、权限、Agent、应用/规则更新、Helper、通用排列。废纸篓提醒并入删除与恢复，语言及版本并入通用；仅保留简短说明、实际错误和必要确认，补充细节放在帮助提示中。

项目扫描目录与预选开关在任务进行中仍可编辑；目录保存不会打断当前扫描，空闲时自动刷新项目产物，忙碌时下次扫描生效。Agent 阈值使用 80%、85%、90%、95%、100% 五档，下次预选计算使用新值；重新计算请求在忙碌时排队，重复点击合并。

项目扫描和执行前复核均不设深度、条目、时长上限，忽略旧兼容参数及 `ScanContext.enforcesEntryBudgets`；Git 状态与项目安装包内容核验同样不设工作预算，扫描仍可取消。识别 requirements.txt、setup.py、setup.cfg、Pipfile 等 Python 项目标记，并仅将带有 pyvenv.cfg 的 .venv/venv/env 识别为虚拟环境产物。扫描后默认显示全部项目，保留默认勾选设置与用户主动切换的筛选；读取失败的提示包含具体路径。凭证、嵌套版本库及永久保护检查继续生效。

结果页共用单行筛选栏：全选（如有）、分段范围、排序、其他操作依次靠左，搜索框固定靠右；窄窗口统一采用紧凑宽度和间距，所有控件保持完整、单行且不横向滚动。各页搜索框在相同窗口宽度下等宽（紧凑 170 pt，宽屏 260 pt）。搜索使用原生搜索框，输入后显示框内清空按钮；名称和路径提示不再提及证据。栏内不再显示项目数量，Agent 下方分析状态、汇总及分组数量继续保留。Agent 搜索覆盖 Skill 元数据及 MCP 名称、路径、平台、服务器名，筛选不取消隐藏选择。

筛选栏内不使用竖向分割线；各页共用 tab 每段基础宽度、下拉框宽度及分组间距，长文字 tab 保留必要宽度。下拉框紧凑/常规宽度分别为 120/140 pt。总清理操作栏统一使用“已选项目 / Selected”，覆盖推荐与手动已选项。

系统清理对精确归属的 `Library/Caches` 更新缓存进行区分：内部链接只允许指向缓存内部；下载的应用包必须通过完整签名、Bundle ID 及已知 Team ID 校验，其封装程序资源不再按 `messages`、`cookies`、`.env` 等名称误判为用户数据。此类缓存归入“建议保留”，仅手动选择；执行前重新检查。真实凭证、越界链接、用户永久保护和不完整扫描继续阻止清理。卸载关联清单在应用运行时保留于预备计划中，缓存清理不依赖卸载操作。

Agent 扫描共用按文件版本校验的 Skill/MCP 解析缓存，复用能力清单与资产扫描的解析结果；深层内容变化、权限或链接替换会失效，不缓存清理资格。Skill 来源在遍历中追加，结束时一次去重与排序；预读只查看当前 Provider 的待处理区间，避免反复遍历其他 Provider 队列。相关性分析继续使用原有持久化增量索引，界面阶段显示保持不变。

2026-11-23 本机对照：同一 262,043 资产、3,210 Skill、47 MCP 的独立 Agent 扫描从 341.23 秒降至 137.90 秒，资产路径/分类/风险与能力内容摘要一致；新版未变化复扫为 110.96 秒。应用内同权限单次整轮从 11:48 降至 6:50，仍显示复用 3,257 项、无重新分析。计时为本机观测，不作为跨机器固定阈值。

扫描结果发布在串行队列中先冻结最新基线与版本，再由后台任务组装候选索引；回主线程前重新验证扫描代次与模块令牌，并合并当前完成/取消状态，防止并发覆盖与迟到结果发布。新代次复用未改变的候选索引。Dashboard 的大文件阈值读取原始扫描参数，不触发目录树过滤；项目安装包过滤仅访问关联祖先分支，展示树按报告缓存并在更新时失效。
