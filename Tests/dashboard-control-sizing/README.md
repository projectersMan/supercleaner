# Scan 高度和资源页全选标签验证

基于 0.4.8（122），本批处理三个明确 UI 要求：Scan 可见按钮约 28pt → 56pt；本地模型/项目页 Select All 文字完整显示；英文 Project Artifacts 标题统一大小写。扫描速度问题按源码与用户截图解释，不更改扫描范围或首页状态显示策略。

## 逐文件复核

| 文件 | 原因 |
| --- | --- |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 56pt 标签配专用 ButtonStyle，使可见背景和点击区一起变高，保留按压、禁用、焦点及 Button 语义；计时仍在下方，112pt 操作行及共享左右边界保留。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 根因是 NSButton 标题为空而非单纯压缩；顶部传入本地化短标题，组内标题仍为空。顶部控件 92pt、摘要最小 200pt、计数固有宽度，复用 ViewThatFits 分行，不改选择策略或受保护项门禁。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 共用“项目产物”翻译改为 Project Artifacts，一处覆盖侧栏、标题及首页。无新消息或依赖。 |
| [Version.json](../../Version.json) | 本批一次递增 0.4.9（123），App/Helper 统一。 |
| [README.md](../../README.md) | 同步可见高度、全选操作与当前产物入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 记录 56pt 控件、可见标签和共用标题来源。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md) | 记录焦点/禁用语义、窄窗口布局和避免仅设置 accessibilityLabel 的要求。 |
| [实施计划](../../doc/dashboard-all-default-plan.md)、[发布记录](../../doc/release-0.4.9.md)与本目录 | 保留范围、诊断、评分和实际构建/视觉结果。 |

## 扫描速度核查

[LocalAIModelScanner](../../Sources/CleanerCore/LocalAIModelScanner.swift) 检查七类工具的十个固定存储位置，枚举目录并读取身份、大小和元数据指纹，不加载 GB 级权重；自定义存储位置不在这个固定清单中。[ProjectArtifactScanner](../../Sources/CleanerCore/ProjectArtifacts.swift) 只在配置源码根内识别 manifest 和产物目录，跳过一般隐藏目录与 app 包的继续探索；两者都有条目数/时间预算。[SystemScanCoordinator](../../Sources/CleanerCore/SystemScanCoordinator.swift) 并行执行模块，先完成的模块可独立发布。

首页目前按既有约定将 completed/limited 显示为相同绿色完成；用户提供的模型页截图实际含“部分目录未完整检查”提示以及占用保护，不能据绿色勾推断无任何限制。没有从截图推断项目页一定完整，也未新增全盘扫描承诺。

局部建议：可见高度 97、全选标签 100、共用标题 100；全局复用选择状态和控件 99，均执行。该批为 UI 样式/文本修复，截图与真实控件构造直接定位，不新增复述布局的测试；使用既有选择策略回归、包自检和原生截图确认。根目录无 AGENTS.md、CONTEXT.md 或 .trae/rules/project_rules.md。项目为 Swift，无新增依赖，不创建 requirements.txt；保留既有改动，不提交或推送。

## 实际结果

- 语法解析和 `git diff --check` 通过。[固定证书构建](package.log)完整 Release 测试 305 项、0 失败，核心契约和 1259 条双语资源检查通过。
- [完整包验证](verification.log)、[DMG 创建/挂载/签名检查](dmg.log)通过；[安装核对](installation.log)确认 App/Helper 均为 0.4.9（123），严格签名、既有 entitlement 和三个可执行文件与构建一致。
- 原生普通窗口截图确认 Scan 可见背景为 56pt（原约 28pt 的两倍），宽度量级及左边界保留。扫描中禁用外观、按钮下计时、三列和六行完整可见。
- 模型页普通窗口和系统四分之一动作允许的窄窗口中，Select All 与 4/4 数量完整显示；受限提示的 tooltip 明确为工具运行/活动无法确认。项目页窄窗口中标题/侧栏为 Project Artifacts，Select All 与 9/9 数量完整显示，筛选栏自动分行。
- 实际项目全选仅勾选 4 个可清理项，受保护项未加入；再次点击恢复零选择。未点击 Confirm Deletion 或清空废纸篓，验证仅进行只读扫描与临时勾选。
- 更新前旧版结果核对为模型 4 项、项目 8 项；本批只读扫描时项目为 9 项（另含新出现的 worktree 产物），并未把首页绿色完成等同于无任何限制。
- 使用 Return to Previous Size 恢复原窗口，正常退出本批只读扫描后重开最终安装版，留在空闲首页。原数据、偏好目录保留，旧安装备份与自检夹具已清理。逐文件审计见 [最终记录](final-audit.log)，未提交或推送。
