# 资源页 Cleanable 默认筛选与预选

范围：清理中心模块行内 Default 改为 Cleanup；Project Artifacts 和 Local AI Models 新扫描结果有可清理项就显示 Cleanable 并预选这些项，否则显示 All。用户之后调整的勾选/筛选不因导航、无关结果或最终整批汇总而被覆盖。本模块重新扫描成功时重新应用默认。

## 逐文件复核

| 文件 | 修改与必要性 |
| --- | --- |
| [AppModel.swift](../../Sources/CleanerApp/AppModel.swift) | 共用 applyResourceScanDefaults，以现有可清理资格过滤，替换旧模块选择并选择 Cleanable/All；渐进发布只作用于当前完成模块，首次新 generation 完整安装也处理资源，最终汇总和普通回执保留手动决策。新增同模型导航自检，不创建用户 CLI。 |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 行内统计前缀改为 Cleanup/清理，不改计数或首页全部默认队列。 |
| [ResourceCleanupView.swift](../../Sources/CleanerApp/ResourceCleanupView.swift) | 模型页不再提示“默认保留/手动选择”，同步可清理项预选供确认；重新下载及 Ollama 整库说明继续显示。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 三条消息配对替换，仍为 1271 条；占位符一致。 |
| [Version.json](../../Version.json) | 本批 0.4.11（125）递增一次至 0.4.12（126），不因重建再次递增。 |
| [README.md](../../README.md) | 使用者可见的筛选、预选、取消及重新扫描语义，当前产物入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 明确模块发布边界、旧报告 payload 不能提前预选，Core 资格和首页队列独立。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 同步回归与验收要求，移除资源页零预选的过期说明。 |
| [实施计划](../../doc/resource-cleanable-defaults-plan.md)、本目录 | 记录需求、方案反思、评分、逐文件理由及验证。 |

Core 的候选风险、defaultSelection/显式选择标记不改；新 UI 预选复用 ResourceCleanupListPolicy，活动、blocked、不完整或永久保护项继续排除，执行仍要求确认和复验。资源页的预选不会把模型/项目加进首页全部默认清理。它们的 Core 库存规则与原有模型/项目安全测试保持原实现。

局部文案和默认筛选/勾选均 100/100，全局共用资格与发布边界 99/100，均实施。无额外扩展建议。项目为 Swift，无新增依赖，不创建 requirements.txt；根目录无 AGENTS.md 或 .trae/rules/project_rules.md。保留前序未提交修改，不提交或推送。

## 定向回归和独立审查

[红灯](red.log)在旧实现下实际失败“new resource results must show/select Cleanable”。[绿灯](green.log)通过：初次完整/渐进资源结果预选、保护/空集合 All、旧 ID 替换、搜索/排序和其它模块选择保留、无关发布/最终汇总保留用户取消、首页默认队列继续排除资源。既有资源保护/回执/筛选/焦点与默认清理回归同时通过，没有执行清理。

按 requesting-code-review 技能独立只读复查未发现确定缺陷。补充“已有旧报告，新 generation 首先发布无关模块，再陆续发布项目与模型”的 accumulator baseline 回归通过，旧资源不会提前预选，两模块不会互相覆盖。活动、blocked、不完整资格由同一底层策略及既有 [ResourceCleanupListPolicyTests](../CleanerCoreTests/ResourceCleanupListPolicyTests.swift) 覆盖；本模型回归补充永久保护与空回退。

## 最终验收

- [固定证书完整构建](package.log)通过 305 项 Release 测试、0 失败、核心契约及 1271 条双语检查。
- [包验证](verification.log)、[DMG创建/挂载/签名检查](dmg.log)及[安装核对](installation.log)通过。App/Helper 同为 0.4.12（126），严格签名、既有 entitlement 与三个可执行文件均与构建一致。
- 原生只读扫描中，项目页初始 Cleanable，4/9 项显示，Select All 与全部 4 个可清理项为选中，约 4.41 GB；受保护项不在 Cleanable 中。取消 zflow/target 后为 3 项，Select All 为 mixed，切换模型页再回来仍为 3 项且 target 未勾选。
- 模型页当次 4 项均受活动未知/运行保护，正确默认 All、4/4 显示且零勾选。新模型说明与重新下载提醒可见。模型有可清理项及纯空集合由同模型自检覆盖。
- [真实配置前状态](user-config-before.json)与[后状态](user-config-after.json)一致。没有执行真实清理、清空废纸篓、权限或 Helper 注册；[发布记录](../../doc/release-0.4.12.md)同步产物，最终页面与逐文件审计见 [最终记录](final-audit.log)。

行内 Cleanup 前缀已在安装版双语资源及 Dashboard 接线中核对；只读验证仅等待资源模块完成，未将仍在进行的系统/Agent 扫描记为完成。验证后正常退出并重开安装版，最终停留空闲清理中心，窗口尺寸不变，临时勾选不写入磁盘。
