# 历史记录

## 2026-11-24 紧凑模型设置编译交付与中间文件清理

交付 **0.6.23（199）**：[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.6.23.dmg](../build/SuperCleaner-0.6.23.dmg)。空的模型目录列表不再占据固定高度，添加后恢复现有滚动布局，保存/撤销/错误入口独立保留。采用现有 ad-hoc 本地签名。

- 完整 Release XCTest **461 项通过**（Core 399、App 62），发布脚本测试 **18 项通过**；CoreContractChecks、Sparkle 签名互操作及 **1354** 条双语消息检查通过。
- 隐藏编译缓存后全部应用自检及真实模型 **768 维**推理通过，缓存已恢复；包内双语目录与源码一致，已删除空目录占位文案。
- DMG 校验、只读挂载、镜像内签名、App/Helper/Version.json 一致和 **203 个条目**逐项核对通过，镜像已卸载。DMG **299,407,882 字节**；SHA-256：`830a0a1068ce94721b9b5854a352484f1a70e62516337d0eca5e337c9cd23eb1`。
- 按本轮要求清理 **5 个**过渡 DMG，共 **1,496,592,317 字节**；主项目与旧工作树的临时脚本、夹具、探针、克隆和逐轮日志共 **71,426,419 字节**已清理。旧包改为历史文件名记录，保留版本及已有校验事实，当前目录仅保留新包。旧 0.6.14 包在本轮之前已从工作区移除，本轮一并记录删除；旧提交仍可追溯。

本次提交范围汇总相对 6ef0200 的全部待提交修改：系统推荐与深度清理聚合和保护约束、Trash 期间只读扫描、模型自定义路径及原根恢复、模型设置布局与空列表折叠、System 置顶、隐藏项目 DMG 及跨模块归属/选择修复、配套契约/XCTest、MangoDisk 比较与维护文档，以及已核验 App/DMG。`.gitattributes` 让 App 内模型与源码模型共用既有 Git LFS 对象；未增加依赖或修改构建脚本。

逐文件复核：模型设置与两份消息删除空占位；README 更新当前包和空目录使用说明；架构/开发/模型目录/测试索引同步显示与清理约束；历史记录保存结果和旧包清理事实；Version 由标准脚本分配；App 与 DMG 按内容/权限/链接和签名核验。全部业务源码与测试在构建后保持不变。局部建议“空列表不占位”98 分、全局建议“保留配置操作并统一交付验证”96 分、交付建议“清理过渡材料并沿用 LFS”95 分，均已实施。

## 2026-11-24 模型目录空列表收起

按截图要求，没有自定义模型扫描目录时直接省略整个 132pt 列表及空状态文字，保留工具选择、目录计数和 Add Folders。添加目录后恢复原有列表；移除最后一项不隐藏保存、撤销和错误入口。扫描范围、选择及执行规则不变。

逐文件必要性：`ModelStorageRootsSettingsSection.swift` 仅在目录非空时创建 ScrollView；中英文 Localizable.strings 删除无引用的占位文案；README、架构、开发、模型目录说明、测试索引与本历史同步空列表行为。`.gitattributes` 将待交付 App 内的同一模型也交由既有 Git LFS 管理，保证源码、文档、App 和 DMG 可一起入库，避免大模型直接进入 Git 对象。无新增依赖。

局部建议“无内容时不创建固定高度区域”98 分、全局建议“占位折叠不影响配置保存与错误入口”96 分，均已实施。此为可逆展示调整，不增加镜像实现的测试；沿用配置回归与完整构建检查。交付与清理结果见本日 0.6.23 记录。

## 2026-11-24 跨模块归属修复版编译交付

本地交付 **0.6.22（198）**：[SuperCleaner.app](../build/SuperCleaner.app)、`SuperCleaner-0.6.22.dmg`。修复 Agent 完成后覆盖项目目录导致容量/默认选择回退，保留模型目录布局统一、System 置顶及隐藏项目 DMG 预选。使用既有默认 ad-hoc 本地签名，未替换安装副本、提交或推送。

- 完整 **Release XCTest 461 项通过**（Core 399、App 62）；新增 Core 三项/App 三项覆盖六种模块顺序、9.76GB 容量、项目保护、模型手选及人工取消。CoreContractChecks 与 Sparkle 签名互操作通过。
- 隐藏 `.build/` 后包内结构、签名、双语设置、扫描/清理、导航、资源实际渐进发布、响应与 Trash 自检通过；模型产生有效 768 维向量，缓存已恢复。
- 本机只读集成探针的真实项目路径及默认计划在加入 Codex 分类器重叠结果前后保持一致，均为 **9,765,475,527 字节**。未执行用户目录清理。
- DMG 校验、只读挂载、镜像内签名、App/Helper/Version.json 一致及 **203 个条目**逐项核对通过，镜像已卸载。
- DMG **299,406,330 字节**；SHA-256：`db7d4824d6202f0e65711773b03a9dc1b642430720bbe38a4271e3b0462a691a`。

构建逐文件复核：`Version.json` 由标准脚本分配 0.6.22（198）；App 和新 DMG 从修复源码生成并核验；`README.md` 更新当前安装包链接；本历史记录保存真实结果。构建阶段未额外修改业务源码、测试或依赖。局部建议“共享候选归属入口修复覆盖”99 分、全局建议“真实多模块发布/计划/保护及安装包一起验证”99 分，均已完成。0.6.21 在独立自检中被拦截，未制作镜像或交付；补齐实际 Agent 发布选择同步后按标准版本规则重新构建。

文档逐项复核另纠正 README 中过期的“项目预选默认关闭、默认进入 Selected”说明，按当前实现记录为默认开启并进入 All；局部建议“使用说明与已验证默认行为一致”95 分，已实施，仅修改文档。

## 2026-11-24 全扫描结束后项目容量回退修复

用户截图显示四个项目产物约 9.76GB，结束时仅主项目两个目录约 4.5GB。已确认安装和运行均为交付的 0.6.20（196），二进制哈希一致。根因为 Agent 把 worktrees 路径下的构建子目录也泛化为受保护 worktree，而全局按路径去重时 Agent 优先于项目目录，导致项目 .build/build 被替代，原先由父目录覆盖的未勾选 DMG 重新露出。

修复在共享候选归属入口完成：保留原有系统、大文件及副本证明约束，模型和项目的专门判断放在 Agent 泛化枚举之前。没有删除 Agent 清单或放宽 worktree 根、项目自身保护、模型手选及保留件规则，也没有结束时重置用户选择。此前单模块验证遗漏此联动，本轮补充完整模块顺序与应用状态回归。

新增 Core 回归先精确复现 9,756,200,000→4,500,000,000 字节，App 回归复现目录、容量及选择回退。修复后六种模块完成顺序一致，默认与手动取消均保留。本机只读扫描两个真实项目并调用 Codex 实际分类器后，加入 Agent 重叠项前后四条项目路径及 9,765,475,527 字节保持一致。独立包原生自检在真实 installProgressive 入口进一步发现 Agent 按原始清单 ID 清空项目勾选，补入 XCTest 后先失败再修复为只同步最终归属 Agent 的候选。未操作用户文件。

逐文件必要性：`SystemScanReport.swift` 修正统一候选优先级；`AppModel.swift` 使 Agent 选择同步遵循最终候选归属，并在已有资源自检补充真正渐进发布的 Agent 迟到场景；新增 `ProjectModuleOwnershipTests.swift` 验证顺序/容量/保护，新增 `ProjectModuleSelectionTests.swift` 验证项目行/底栏/手动选择，并将实际渐进发布原生检查纳入 XCTest；README、架构、开发、测试索引及本历史记录同步行为和证据。无新增依赖。

局部建议“专门模块归属优先于 Agent 泛化标签”99 分、全局建议“模块顺序、最终计划、真实发布和保护联动验证”99 分，均已实施。最终完整测试与安装包见后续编译交付记录。

## 2026-11-24 配置布局与排序版编译打包

按用户要求，使用现有标准构建脚本交付 **0.6.20（196）**，包含 Model Scan Folders 与 Project Scan Folders 的统一布局，以及推荐/深度清理内 System 固定置顶。已识别项目内 DMG 不再因隐藏路径被排除，并遵循项目预选开关；依赖、凭据、永久保护、链接和保留件检查继续生效。产物为 [SuperCleaner.app](../build/SuperCleaner.app) 与 `SuperCleaner-0.6.20.dmg`，采用现有默认 ad-hoc 本地签名。

- 本轮完整 **Release XCTest 455 项通过**（Core 396、App 59）；CoreContractChecks 和 Sparkle 签名互操作通过。
- 隐藏 `.build/` 后，包内结构、签名、双语设置、扫描/清理、导航、响应、Trash 夹具和独立模型推理验证通过，产生有效 768 维向量，编译缓存已恢复。
- DMG 校验、只读挂载、镜像内签名和 App/Helper/Version.json 版本核对通过，**203 个条目**内容、权限及链接与构建 App 一致；检查后镜像已卸载。
- DMG **299,405,495 字节**，SHA-256：`66f35b133d8b44eab85340514bccc00fb37778037174828800cb73d5ca60c69d`。

首次镜像创建返回系统“资源忙”；确认无残留挂载、无不完整输出且空间充足后，改用本任务 Tests/temporary 下的独立临时目录重试成功，构建和打包脚本未改动。

逐文件复核：`Version.json` 由标准构建分配新版本；`build/SuperCleaner.app` 重新编译、组装和签名；新 `build/SuperCleaner-0.6.20.dmg` 包含 App 与 Applications 拖放快捷方式；`README.md` 更新当前安装包链接；`docs/custom-model-paths.md` 记录最新布局的交付版本；本历史记录保存本次核验结果。业务源码、测试、依赖及构建脚本无额外变更。局部建议“沿用统一版本构建入口” **98 分**、全局建议“独立运行并核对镜像和 App 内容” **99 分**，均已执行。未替换安装副本、提交或推送。

## 2026-11-24 隐藏项目 DMG 纳入预选

用户明确要求截图中的 DMG 不应因隐藏路径被保护。仅在已识别项目的 DMG 扫描及副本分析中允许隐藏路径，保留项目预选开关；通用大文件推荐范围不变。选中父目录时安装包由父目录覆盖，不重复计量。凭据和运行时目录、应用包、链接、永久保护、未知 Git 状态及验证失败继续阻止处理；副本保留件及其父目录仍保护。

新增回归先复现隐藏工作树 DMG 资格/预选和副本分析失败。修复后 26 项定向回归通过。另用实际保护配置只读重扫截图工作树：`SuperCleaner-0.6.15.dmg` 由 blocked 变为 review、可选择并被默认计划覆盖，未操作用户文件。最终完整测试与产物见后续打包记录。

逐文件必要性：`LargeFileCleanupScope.swift` 仅按显式许可放行隐藏目录，并保留原来被隐藏限制覆盖的凭据目录保护；`LargeFileContentAnalyzer.swift` 将项目许可同时用于副本分析和安装包资格校验；`ProjectArtifacts.swift` 在已识别项目链中传入许可；`ProjectInstallerTests.swift` 增加三个真实目录回归；README、架构、开发、测试索引及本历史记录同步行为。局部建议“已识别项目不因隐藏路径失去资格”97 分、全局建议“扫描/副本证明/执行保持一致且保留真实保护”99 分，均已实施。

收到补充要求时已中止正在运行的 0.6.19 构建，按既有版本规则不回退已分配号码，最终重新构建使用下一版本。

## 2026-11-24 配置样式统一与 System 置顶

按用户截图，将 Model Scan Folders 对齐 Project Scan Folders 的原生分组、目录计数、Add Folders、目录图标、路径、Remove、行高、分隔线和滚动布局，保留必要的工具选择。System 在推荐和深度清理各组中固定排第一，应用仍按容量排序，候选与清理资格不变。

针对截图中第二个同名 supercleaner 做了只读核对：它是 Codex 工作树，与主项目按路径独立分组。现场使用实际保护配置重扫，`.build`、`build` 均可选择并进入开启预选时的默认集合；`SuperCleaner-0.6.15.dmg` 单独命中通用安装包的隐藏路径限制，显示 inspection-failed 保护。这不表示镜像已损坏，也不能由预选开关覆盖。截图没有当时完整报告，无法据此还原当时目录未显示的具体原因，故未修改项目选择或保护规则。没有执行真实清理。

逐文件复核：

| 文件 | 必要改动与原因 |
| --- | --- |
| [ModelStorageRootsSettingsSection.swift](../Sources/CleanerApp/ModelStorageRootsSettingsSection.swift) | 复用项目配置布局，补齐空状态、移除帮助、无障碍标签与读取错误入口。 |
| [SystemCleanupApplicationGroup.swift](../Sources/CleanerCore/SystemCleanupApplicationGroup.swift) | 按稳定分组标识置顶 System，保留应用原容量顺序。 |
| [SystemCleanupApplicationGroupTests.swift](../Tests/CleanerCoreTests/SystemCleanupApplicationGroupTests.swift) | 新增 System 容量较小、应用名也叫 System 和缺少 System 时的排序回归。 |
| [英文消息](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 统一标题大小写并增加空列表提示。 |
| [中文消息](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 增加对应空列表提示。 |
| [README.md](../README.md) | 说明配置一致性及 System 排序。 |
| [architecture.md](architecture.md) | 记录共享排序边界，避免改变清理分类与资格。 |
| [development.md](development.md) | 固定配置布局和共享排序要求。 |
| [custom-model-paths.md](custom-model-paths.md) | 删除旧折叠样式说明，对齐当前界面。 |
| [history.md](history.md) | 记录项目未预选的现场证据与本轮验证。 |

验证：System 排序新增测试先复现 2 个失败断言；完整 Debug XCTest **452 项通过**（Core 393、App 59），CoreContractChecks 通过。用独立夹具生成并核对 760/1000pt、浅/深色四张原生设置截图，临时截图测试入口已移除。双语 **1,355 条**、文档链接及 diff 空白检查通过。业务修改没有引入依赖；项目扫描、预选及执行保护代码未改动。

局部建议“复用现成设置布局” **98 分**、全局建议“共享入口固定 System 顺序且保留选择语义” **97 分**，均已实施。本轮为源码修改，版本仍为 0.6.18（194），既有 App/DMG 未重新生成，未安装、提交或推送。

## 2026-11-24 自定义模型目录版重新编译打包

用户要求本地重新编译打包，使用现有标准脚本从包含自定义模型目录设置的主项目源码构建 **0.6.18（194）**，保留原有系统清理策略。采用现有默认 ad-hoc 本地签名，产物为 [SuperCleaner.app](../build/SuperCleaner.app) 与 `SuperCleaner-0.6.18.dmg`。未安装、提交或推送。

- 本轮完整 **Release XCTest 451 项通过**（Core 392、App 59）；CoreContractChecks 与 Sparkle 签名互操作通过。
- 隐藏 `.build/` 后执行包内结构、签名、双语设置、扫描/清理、导航、响应和 Trash 夹具自检；包内模型产生有效 768 维向量，缓存已恢复。
- DMG 校验、只读挂载、镜像内签名、App/Helper/Version.json 版本一致性及 **203 个条目**逐项一致检查通过，镜像已卸载。
- DMG **299,361,289 字节**；SHA-256：`9f31dc8be15165d32de34cf2adee229591691940eaad9ca51f1446b6685f92bd`。

逐文件复核：`Version.json` 由标准构建分配版本；`build/SuperCleaner.app` 及新 DMG 由最终源码生成；`README.md` 链接本次可用镜像；`docs/custom-model-paths.md` 更新交付状态；本历史记录保存验证事实。业务源码、测试、依赖、构建脚本未修改。局部建议“使用既有标准流程统一分配版本” **98 分**、全局建议“隔离构建缓存验证并逐文件核对镜像” **99 分**，均已执行。

## 2026-11-24 自定义本地模型目录

按用户要求，仅将路径配置接入 0.6.17 设置页。固定扫描范围保持原十个位置；自定义目录按工具布局识别，不增加环境变量或安装位置推断。保存、扫描、首页计划、执行复验和 Ollama 原根恢复共用根归属；坏配置不影响系统清理。逐文件必要性与建议评分见 [自定义模型目录](custom-model-paths.md)。

先以真实目录复现旧版忽略自定义模型根，再实现并验证。最终 Debug XCTest **451 项通过**（Core 392、App 59），新增 8 项回归；CoreContractChecks 全部通过，Python **18 项通过**，双语 **1,354 条**及文档链接检查通过。旧固定路径测试原来把所有供应商枚举等同于固定路径供应商；改为固定集合断言，并补测 ModelScope/ComfyUI 仅从配置发现。版本、现有 App/DMG 和安装副本不变；本轮未打包、提交或推送，没有新增依赖。

当前实现和验证流程分别以 [架构](architecture.md) 与 [开发指南](development.md) 为准。

2026-11-23 整理：早期 `doc/`、重复架构/开发文档、已完成计划、历史发布记录和专项测试日志合并到一个 [压缩归档](archive/legacy-materials-2026-11-23.tar.gz)。归档保留原始路径、文件内容及 `MANIFEST.sha256.json`，归档时逐文件 SHA-256 校验通过。需要查看旧版本事实时按归档原文阅读，不把旧机器安装或签名记录当作当前验证结果。

解压到仓库外的独立目录即可查看历史内容：

```sh
mkdir -p /tmp/supercleaner-history
tar -xzf docs/archive/legacy-materials-2026-11-23.tar.gz -C /tmp/supercleaner-history
```

## 2026-11-24 系统清理改为两个展示分组

按用户截图要求，原推荐与原 Deep Cleanup 合并到推荐清理并默认勾选；原 Keep and Protected 放入深度清理，去掉第三个分组。以截图同一份候选集合计算，推荐应由 15 + 23 合并为 38 项，深度复核承接原 118 项；实际重新扫描数量可能变化。

底层四种证据分类继续区分低影响、可再生、需保留与受保护，作为检查与影响说明的依据。展示聚合和默认选择共用集合；深度组仍不自动勾选，逐项同意、敏感内容和不完整扫描保护继续生效。合并没有扩大扫描根或执行范围。

本轮逐文件复核：

| 文件 | 本轮必要修改 |
|---|---|
| [GuidedCleanupView.swift](../Sources/CleanerApp/GuidedCleanupView.swift) | 只展示推荐和深度两个区，删除第三个折叠状态与展示，说明缓存下载/重建成本。 |
| [CleanupRecommendationPolicy.swift](../Sources/CleanerCore/CleanupRecommendationPolicy.swift) | 在现有 breakdown 中统一两组聚合；推荐默认包含已验证可再生缓存，手选与保护数据排除。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 推荐模式的基础集合同步包含可再生项，取消选择和排除记录与默认计划一致。 |
| [Components.swift](../Sources/CleanerApp/Components.swift) | 可再生项徽章与新推荐分组一致，风险说明不再沿用旧深度定义。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 修订可再生证明注释，仍保留重建成本与可删除性的区别。 |
| [英文消息](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 增加两组说明，移除不用的第三组标题与旧默认说明，修正风险文本。 |
| [中文消息](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 与英文逐条对应，保持占位符与分组语义一致。 |
| [CleanupRecommendationPolicyTests.swift](../Tests/CleanerCoreTests/CleanupRecommendationPolicyTests.swift) | 推荐默认集合包含可再生项，仍排除手选、活动未验证和受保护项目。 |
| [CleanupCenterPlanTests.swift](../Tests/CleanerAppTests/CleanupCenterPlanTests.swift) | 活动但已验证的缓存随推荐默认进入总计划，取消和重新选择结果一致。 |
| [SystemCleanupClassificationRegressionTests.swift](../Tests/CleanerCoreTests/SystemCleanupClassificationRegressionTests.swift) | 四个真实下载缓存进入推荐，未知/历史数据及受保护内容进入深度复核且不自动选择。 |
| [ApplicationGeneratedDataTests.swift](../Tests/CleanerCoreTests/ApplicationGeneratedDataTests.swift) | 网络缓存和日志默认纳入，离线及共享数据继续手选。 |
| [CacheReferenceCleanupTests.swift](../Tests/CleanerCoreTests/CacheReferenceCleanupTests.swift) | 已验证无引用缓存可推荐；登记变化及不完整引用仍阻止默认处理。 |
| [CleanupModeContract.swift](../Sources/CoreContractChecks/CleanupModeContract.swift) | 推荐模式与合并后集合一致，保持跨模块选择。 |
| [CleanupRecommendationContract.swift](../Sources/CoreContractChecks/CleanupRecommendationContract.swift) | 推荐策略纳入已验证可再生项，底层保护和手选证据不变。 |
| [README.md](../README.md) | 更新两组使用说明、默认选择及清理后的下载/构建影响。 |
| [architecture.md](architecture.md) | 区分底层证据分类与用户看到的两个分组。 |
| [development.md](development.md) | 固定聚合、默认选择、人工取消和最终计划的一致性要求。 |
| [system-cleanup-scanning.md](system-cleanup-scanning.md) | 用两组替代三组说明，明确深度中的手选及保护约束。 |
| [history.md](history.md) | 记录本次调整、逐文件必要性与验证结果。 |
| [Version.json](../Version.json) | 标准构建脚本分配 0.6.17（193），用于 App、Helper 与镜像一致性验证。 |
| [SuperCleaner.app](../build/SuperCleaner.app) | 从本轮最终源码重新生成并进行独立运行校验。 |
| `SuperCleaner-0.6.17.dmg` | 新建本轮安装镜像，逐文件核对与已验证 App 一致。 |

局部建议：删除第三组并复用现有折叠列表 **98 分**；全局建议：两组显示、默认勾选与最终计划共用聚合集合 **99 分**，均已实施。没有新增依赖或动态安装逻辑。

本地交付为 **0.6.17（193）**。验证结果：

- 修改前新增预期在 3 项 Core、6 项 App 测试中复现 **8 个失败断言**；修改后完整 Release XCTest **443 项通过**（Core 386、App 57），无失败。正式打包复用这次完整结果，不重复运行 XCTest。
- CoreContractChecks、Sparkle 签名互操作与 **1,347 条双语消息**检查通过；独立只读复核未发现遗留问题。
- App 结构、签名、双语设置、扫描/清理、导航、响应与 Trash 夹具自检通过；隐藏 `.build/` 后运行通过，模型产生有效 768 维向量，编译目录已恢复。
- DMG 校验、只读挂载、镜像内签名、App/Helper/Version.json 一致性通过，**203 个条目**逐项一致，检查后镜像已卸载。
- 当前 Markdown 仓库内路径及 `git diff --check` 通过。首次镜像创建返回“资源忙”；检查无残留挂载、空间充足且无不完整输出后，同一命令重试成功，打包脚本未修改。

镜像 **299,208,617 字节**，SHA-256：`2c8da80ff3e38a0ca83f50caf74d7a6af123dbcdb7c86b5c651948bee47f10ba`。沿用现有 ad-hoc 本地签名，未替换已安装应用、提交或推送。完整日志与产物清单位于 `Tests/temporary/two-cleanup-groups-20261124/`。

## 2026-11-24 废纸篓任务独立与系统清理分级

本次修正清空系统废纸篓期间的全界面禁用，并把低影响推荐、可再生深度清理和需逐项同意的数据分开。浏览、筛选、选择、扫描与清空独立；会新增或恢复文件的清理、卸载、恢复、永久删除等操作继续互斥。全程未实际清空用户废纸篓或删除用户缓存。

只读核对本机可见的 26 份回执：对应截图的最近会话共处理 1,782 项、14,043,446,413 字节，全部成功，没有失败或跳过。截图四个下载缓存路径未出现在这些回执及祖先/后代覆盖记录中；回执不保存当时完整扫描及未选项目，因此不能据此认定它们清理失败、曾被选择或不应清理。用户具体文件清单保留在本机临时验证目录，不写入发布文档。

逐文件复核如下，各项均服务于本次任务边界、分类语义及其验证；未修改依赖，没有新增动态安装逻辑。

| 文件 | 必要变更及原因 |
|---|---|
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 只读扫描入口与续扫移除清空门禁；保留所有删除和恢复门禁；系统组选择不能替代逐项同意，清空选择仍可撤销全部手选。 |
| [ContentView.swift](../Sources/CleanerApp/ContentView.swift) | 移除清空期间的整页禁用，使浏览、筛选和选择继续可用。 |
| [HistoryView.swift](../Sources/CleanerApp/HistoryView.swift) | 恢复与永久删除按钮在清空期间单独禁用，与模型门禁一致。 |
| [GuidedCleanupView.swift](../Sources/CleanerApp/GuidedCleanupView.swift) | 三个展示区严格对应真实分类；保留项不混入深度；System 子组不批量授权手选数据。 |
| [Components.swift](../Sources/CleanerApp/Components.swift) | 风险说明区分低影响推荐和可再生深度，不再把可再生等同于默认推荐。 |
| [NavigationPresentationFixture.swift](../Sources/CleanerApp/NavigationPresentationFixture.swift) | 低影响日志夹具显式声明推荐；夹具辅助函数改为类型方法。 |
| [TrashEmptyingCheck.swift](../Sources/CleanerApp/TrashEmptyingCheck.swift) | 自检日志夹具显式声明推荐，避免依赖缺省推断。 |
| [CleanupRecommendationPolicy.swift](../Sources/CleanerCore/CleanupRecommendationPolicy.swift) | 推荐要求 safe 与明确默认许可；深度要求可再生证明；未知、用户数据和历史残留保留。 |
| [CleanupModeSelectionState.swift](../Sources/CleanerCore/CleanupModeSelectionState.swift) | 默认推荐模式，恢复推荐/深度/自定义三个明确选择入口。 |
| [ApplicationCleanupScanner.swift](../Sources/CleanerCore/ApplicationCleanupScanner.swift) | 分开网络下载缓存与低影响本地派生缓存、日志；共享和离线内容仍手选。 |
| [CleanupRuleEngine.swift](../Sources/CleanerCore/CleanupRuleEngine.swift) | 引用证明只支持深度资格；复用敏感内容检测，保留执行复验。 |
| [HistoricalResidueScanner.swift](../Sources/CleanerCore/HistoricalResidueScanner.swift) | 未发现所有者不再证明可丢弃；历史数据逐项选择，敏感后代受保护。 |
| [ResourceCleanupListPolicy.swift](../Sources/CleanerCore/ResourceCleanupListPolicy.swift) | 总计划允许已验证可再生运行时缓存，避免与系统清理页选择不一致；其它活动资源仍排除。 |
| [Models.swift](../Sources/CleanerCore/Models.swift) | 注释明确可丢弃证明与低影响推荐是两个条件。 |
| [base-rules.json](../Sources/CleanerCore/Resources/base-rules.json) | pip/npm/SwiftPM/Homebrew 等下载或重建缓存归深度且不默认选；未知缓存保留。 |
| [英文消息](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 补齐分级、默认选择与影响说明。 |
| [中文消息](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 与英文逐条对应，保持占位符一致。 |
| [CleanupModeContract.swift](../Sources/CoreContractChecks/CleanupModeContract.swift) | 固定默认推荐及三个模式契约。 |
| [CleanupRecommendationContract.swift](../Sources/CoreContractChecks/CleanupRecommendationContract.swift) | 可再生缓存应属深度，低影响夹具需明确许可。 |
| [CoreReadOnlyContract.swift](../Sources/CoreContractChecks/CoreReadOnlyContract.swift) | 未知缓存可以显式预览，但不能出现在默认预览。 |
| [DefaultCleanupPolicyContract.swift](../Sources/CoreContractChecks/DefaultCleanupPolicyContract.swift) | 默认方案仅含推荐项，保持手动选择独立。 |
| [RuleEngineContract.swift](../Sources/CoreContractChecks/RuleEngineContract.swift) | 通用缓存改为保留，不降低敏感后代和执行复验要求。 |
| [SystemCleanupContract.swift](../Sources/CoreContractChecks/SystemCleanupContract.swift) | 同步网络缓存深度、历史数据保留与分组结果。 |
| [CleanupCenterPlanTests.swift](../Tests/CleanerAppTests/CleanupCenterPlanTests.swift) | 验证含活动标记的深度手选准确进入总计划，以及保留组不能批量授予逐项同意。 |
| [TrashTaskIndependenceTests.swift](../Tests/CleanerAppTests/TrashTaskIndependenceTests.swift) | 验证扫描、模块刷新和选择独立；清理、卸载、恢复和永久删除继续被拦截。 |
| [SystemCleanupClassificationRegressionTests.swift](../Tests/CleanerCoreTests/SystemCleanupClassificationRegressionTests.swift) | 覆盖截图四个真实规则、应用缓存分级、字段缺失和敏感历史残留。 |
| [ApplicationCleanupExecutionMetadataTests.swift](../Tests/CleanerCoreTests/ApplicationCleanupExecutionMetadataTests.swift) | 执行元数据测试同步网络缓存不默认选，继续验证手选与复验字段。 |
| [ApplicationGeneratedDataTests.swift](../Tests/CleanerCoreTests/ApplicationGeneratedDataTests.swift) | 分别验证网络缓存深度、本地派生缓存推荐和离线内容手选。 |
| [CacheReferenceCleanupTests.swift](../Tests/CleanerCoreTests/CacheReferenceCleanupTests.swift) | 引用检查可以支持深度，不支持默认推荐。 |
| [CleanupClassificationTests.swift](../Tests/CleanerCoreTests/CleanupClassificationTests.swift) | 历史残留保留、通用未知缓存手选，维持保护断言。 |
| [CleanupPerformanceTests.swift](../Tests/CleanerCoreTests/CleanupPerformanceTests.swift) | 推荐夹具显式许可，保留原规模和性能验证。 |
| [CleanupRecommendationPolicyTests.swift](../Tests/CleanerCoreTests/CleanupRecommendationPolicyTests.swift) | 断言可再生不等于默认推荐，用户数据和敏感内容不混入。 |
| [DefaultCleanupSelectionTests.swift](../Tests/CleanerCoreTests/DefaultCleanupSelectionTests.swift) | 更新默认推荐夹具，避免把缺失字段当成低影响。 |
| [ScannerTests.swift](../Tests/CleanerCoreTests/ScannerTests.swift) | 更新未知缓存默认值断言，临时素材限制在 Tests/temporary。 |
| [SystemCleanupApplicationGroupTests.swift](../Tests/CleanerCoreTests/SystemCleanupApplicationGroupTests.swift) | 分组测试使用明确许可的推荐夹具。 |
| [README.md](../README.md) | 用户说明同步三类内容、清空与只读任务独立、手选进入总计划。 |
| [architecture.md](architecture.md) | 记录策略与界面共用分级、写操作互斥边界。 |
| [development.md](development.md) | 补充本轮回归入口和不得混淆的分类条件。 |
| [system-cleanup-scanning.md](system-cleanup-scanning.md) | 删除过时描述，统一扫描、影响、同意、执行和回执判读。 |
| [history.md](history.md) | 记录本轮逐文件必要性、验证与本地交付事实。 |
| [Version.json](../Version.json) | 由标准构建脚本分配新版本，保证 App、Helper 与镜像一致。 |
| [SuperCleaner.app](../build/SuperCleaner.app) | 根据最终源码重新生成并验证的本地应用，不替换已安装副本。 |
| `SuperCleaner-0.6.16.dmg` | 封装经过独立运行校验的同一 App，供安装复测。 |

局部建议：解耦清空和只读操作 **98 分**；全局建议：分类、默认选择、组同意与最终计划使用一致语义 **99 分**。两项均已实施，独立复核发现的活动缓存遗漏和整组授权问题一并补齐。

最终本地交付为 **0.6.16（192）**；`0.6.15（191）` 是独立复核补齐前的中间构建，未生成交付镜像。最终验证：

- Release XCTest 共 **443 项通过**（CleanerCore 386 项、CleanerApp 57 项），Python 测试 **18 项通过**。
- CoreContractChecks、Sparkle 签名互操作及 **1,347 条双语消息**检查通过。新增总计划与组同意测试先复现 7 个失败断言，修正后完整通过；测试未放宽安全保护。
- 独立只读复核确认活动缓存总计划、逐项同意及撤销选择问题均闭环，没有遗留 Important 或 Critical 问题。
- App 结构、签名、双语、扫描/清理/恢复边界、权限、导航、响应与 Trash 自检通过。隐藏 `.build/` 后自检及有效 768 维模型向量检查通过，编译目录已恢复。
- DMG 校验、只读挂载、镜像内签名与 App/Helper/Version.json 一致性通过，**203 个条目**逐项一致，校验后镜像已卸载。
- 当前 19 份 Markdown 的仓库内文件引用检查通过；历史旧包和仓库外本机视觉资料引用单独排除，未将其计为已验证的当前文件。

DMG 为 **299,210,586 字节**，SHA-256：`6ce19e8e94ac1e1d84eae87589758b22d0915b1520e94933cf3c9838281607e6`。采用现有 ad-hoc 本地签名；本轮源码、文档与产物保留在本地，未提交或推送。完整验证日志与产物清单位于 `Tests/temporary/trash-and-cleanup-20261124/`。

## 2026-11-24 本地重编译与打包

本次从提交 `4381608` 的源码重新编译，最终本地交付为 **0.6.14（190）**：

- [SuperCleaner.app](../build/SuperCleaner.app)
- `SuperCleaner-0.6.14.dmg`，299,206,446 字节。

首次构建分配 `0.6.13（189）` 后，原有工具栏布局回归测试发现英文应用范围四段控件的原生最小宽度为 352 pt，紧凑布局只分配了 348 pt。[ReviewToolbar.swift](../Sources/CleanerApp/ReviewToolbar.swift) 将每段宽度从 87 调至 88 pt，并把紧凑控件间距从 4 调至 3 pt，保持 760 pt 最小内容区可完整显示。原有中英文、多页面和多窗口宽度回归测试先失败、修改后通过，没有放宽断言。按现有失败构建不回退版本号的规则，重新运行构建得到 `0.6.14（190）`。

验证结果：

- Release XCTest 共 430 项通过（CleanerCore 379 项、CleanerApp 51 项），Python 版本及签名测试 18 项通过。
- CoreContractChecks、Sparkle 签名互操作、1,335 条双语消息及当前文档链接检查通过。
- App 结构、签名、双语设置及扫描、清理、权限、导航、响应和 Trash 自检通过。
- 隐藏 `.build/` 后自检通过，包内模型生成了有效的 768 维向量，检查结束后原编译目录已恢复。
- DMG 校验、只读挂载、镜像内签名和 App/Helper/Version.json 版本一致性通过；203 个目录、文件和链接条目与构建产物逐项一致，镜像已卸载。

DMG SHA-256：`a03f2fd00a4bc8aa9a1a81984619969ce150ce5b626fae8c600e3db64d76e0ba`。

本次使用默认 ad-hoc 本地签名，未作为 Developer ID 公证发行包发布。`build/` 已从 Git 忽略规则中移除，版本化 DMG 继续使用现有 Git LFS 属性；编译缓存和过程日志分别保留在被忽略的 `.build/` 与 `Tests/temporary/`。本次过程日志在 `Tests/temporary/rebuild-0.6.13-20261124/` 和 `Tests/temporary/rebuild-0.6.14-20261124/`，未替换已安装应用。

## 发布索引

| 历史版本 | 原记录标题 |
| --- | --- |
| 0.6.0 | 0.6.0（176） |
| 0.5.30 | 0.5.30（175） |
| 0.5.29 | 0.5.29（174） |
| 0.5.28 | 0.5.28（173） |
| 0.5.27 | 0.5.27（172） |
| 0.5.25 | 0.5.25（170） |
| 0.5.24 | 0.5.24（169） |
| 0.5.22 | 0.5.22（167） |
| 0.5.21 | 0.5.21（166） |
| 0.5.19 | 0.5.19（164） |
| 0.5.18 | 0.5.18（163） |
| 0.5.17 | 0.5.17（162） |
| 0.5.16 | 0.5.16（161） |
| 0.5.15 | 0.5.15（160） |
| 0.5.11 | 0.5.11（156） |
| 0.5.10 | 0.5.10（155） |
| 0.5.0 | 0.5.0（145） |
| 0.4.30 | 0.4.30 (144) |
| 0.4.29 | 0.4.29 (143) |
| 0.4.28 | 0.4.28 (142) |
| 0.4.27 | 0.4.27 (141) |
| 0.4.26 | 0.4.26（140） |
| 0.4.25 | 0.4.25（139） |
| 0.4.24 | 0.4.24（138） |
| 0.4.23 | 0.4.23（137） |
| 0.4.22 | 0.4.22（136，中间测试包） |
| 0.4.20 | 0.4.20（134） |
| 0.4.19 | 0.4.19（133，中间验证包） |
| 0.4.18 | 0.4.18（132，中间验证包） |
| 0.4.17 | 0.4.17（131）中间验证包 |
| 0.4.16 | 0.4.16（130） |
| 0.4.14 | 0.4.14（128）本地交付 |
| 0.4.13 | 0.4.13（127）本地交付 |
| 0.4.12 | 0.4.12（126）本地交付 |
| 0.4.11 | 0.4.11（125）本地交付 |
| 0.4.10 | 0.4.10（124）本地交付 |
| 0.4.9 | 0.4.9（123）本地交付 |
| 0.4.8 | 0.4.8（122）本地交付 |
| 0.4.7 | 0.4.7（121）本地交付 |
| 0.4.6 | 0.4.6（120）本地交付 |
| 0.4.5 | 0.4.5（119）本地交付 |
| 0.4.4 | 0.4.4（118）本地交付 |
| 0.4.3 | 0.4.3（117）本地交付 |
| 0.4.2 | 0.4.2（116）重新编译与打包 |
| 0.3.30 | SuperCleaner 0.3.30（104） |
