# Agent 默认空列表回退

大文件初始已为 All Large Files，保留原行为；没有新增可删除范围。Agent 自动默认按当前 Skill/MCP 类型和平台判断，已选中列表有内容则 Selected，否则 All。用户主动选择后保留其范围，即使 Selected 为空。异步建议到达、类型或平台变化只更新自动默认，不修改实际选择资格或预选策略。

## 逐文件复核

| 文件 | 修改与必要性 |
| --- | --- |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 用 Published 可选手动覆盖保存用户意图，同名可写计算属性继续服务现有 Picker/列表/空态。自动判断复用 Skill plannedForDeletion 和 MCP selectedIDs；类型切换清理两类可见缓存。每轮列表过滤只读取一次有效范围，避免逐条计算导致平方复杂度。 |
| [AppModel 自检](../../Sources/CleanerApp/AppModel.swift) | 增加默认空回退、选择变化、平台/类型/缓存切换、手动保留和大文件原 All 默认回归。内存夹具不再先设置手动 All；旧批量/清空测试显式选 All，继续测原来的手动行为。 |
| [Version.json](../../Version.json) | 从 0.4.12（126）递增一次至 0.4.13（127），App/Helper 统一。 |
| [README.md](../../README.md) | 说明自动 Selected/All 与手动筛选的区别、大文件原 All 默认。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 记录依赖当前类型/平台的默认解析、可选覆盖及缓存依赖，不变更选择资格。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 记录回归与性能要求，类型切换时不能沿用另一种有效范围的缓存。 |
| [实施计划](../../doc/agent-empty-default-scope-plan.md)、本目录 | 方案反思、价值评分、逐文件理由与实际验收证据。 |

大文件 View 和筛选规则无需修改；Agent View 继续绑定同名可写属性，不新增第二套范围状态或产品入口。无新本地化消息或依赖，双语资源仍为 1271 条。项目为 Swift，不创建 requirements.txt；根目录无 AGENTS.md 或 .trae/rules/project_rules.md。保留前序所有未提交改动，不提交或推送。

局部空回退 100/100、保留手动筛选 99/100，全局缓存及线性过滤 99/100，均实施；大文件现有默认符合要求，不增加额外逻辑。

## 定向回归与审查

- [红灯](red.log)：旧实现实际失败 empty default Agent Selected scope must show All。
- [绿灯](green.log)：自动 All/Selected、迟到选择、移除最后一项、Skill/MCP 和平台切换、缓存失效、手动 All/空 Selected 与导航保留通过。大文件默认 All 及手动空重复范围保留通过。
- 同一自检还通过原 1000 Skills × 100 缓存读取、异步预选调度、Skill/MCP 批量选择和 3203 项清空性能门禁；没有执行清理。
- 按 requesting-code-review 技能独立只读复查未发现确定缺陷或阻塞漏测；确认计算属性仍支持 SwiftUI Binding，私有 Published 手动覆盖及原选择/类型/平台事件提供界面更新，自动判断与实际列表一致。

## 最终验收

- [固定证书构建](package.log)通过 305 项 Release 测试、0 失败，核心契约及 1271 条双语检查通过。
- [包验证](verification.log)、[DMG创建/挂载/签名检查](dmg.log)和[安装核对](installation.log)通过；App/Helper 同为 0.4.13（127），三个可执行文件与构建一致，严格签名及既有 entitlement 不变。
- 原生只读扫描中，大文件的 All Large Files 默认选中；随后取消本批无需验证的系统/应用扫描。Agent 清单元数据就绪时有 1022 Skills、45 MCP 配置，尚无目录级候选选择，Skills/MCP 的 Scope 均自动为 All，清单可见。
- 原生手动选择 Selected 后切换到 Skills 仍保持 Selected；取消本批未完成 Agent 扫描后显示 No selected Skills；再手动 All 时完整元数据清单恢复。证明同名计算属性的 SwiftUI Binding 与实际列表同步。
- 未等待目录级扫描和推理完整完成，不将元数据清单声称为可删除内容；有选择自动 Selected、后续预选变化和平台切换由模型夹具覆盖。没有点击真实清理、清空废纸篓、权限或 Helper 注册。
- 最终正常退出验证运行，重开安装版至空闲清理中心，窗口尺寸不变。[发布记录](../../doc/release-0.4.13.md)同步产物，逐文件最终检查见 [审计记录](final-audit.log)。
