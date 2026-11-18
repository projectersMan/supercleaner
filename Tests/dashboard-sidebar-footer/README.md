# 侧栏容量与清理中心底栏

| 文件 | 修改与必要性 |
| --- | --- |
| [CleanupActionBars.swift](../../Sources/CleanerApp/CleanupActionBars.swift) | 共享条只负责内容；清理中心使用共享 SidebarSurface，维度条在调用处保留 bar 背景。移除原生材质桥接，改为相同不透明系统色源，不写死 RGB。 |
| [Components.swift](../../Sources/CleanerApp/Components.swift) | SidebarSurface 统一提供系统窗口底色与 5% 系统前景叠加，跟随深浅外观；不透明色源消除位置透色差异。 |
| [ContentView.swift](../../Sources/CleanerApp/ContentView.swift) | List 的底部安全区放硬盘图标、Disk Space 标题、容量条和可用空间，各页面均可见；隐藏 List 原背景后与底栏共用同一底色；继续使用 AppModel，保留加载/失败状态。 |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 删除首页磁盘区及无用指标辅助函数，扫描和累计清理保持原左右边界，Elapsed 回到按钮右侧并垂直居中。 |
| [英文资源](../../Sources/CleanerCore/Resources/en.lproj/Localizable.strings)、[中文资源](../../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 新增一条可用空间文案，保持占位符配对。 |
| [Version.json](../../Version.json) | 编译脚本保留已开始后中断的 0.4.21（135），随后完整编译分配中间包 0.4.22（136），最终展示调整再分配 0.4.23（137）；不手动回退或 bump。 |
| [README](../../README.md)、[doc 架构](../../doc/architecture.md)、[doc 开发](../../doc/development.md)、[docs 架构](../../docs/architecture.md)、[docs 开发](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 同步新的侧栏容量与底栏外观、版本和操作说明；修正现行 README 中上一轮无效的全屏可见性描述。 |
| [计划](../../doc/dashboard-sidebar-footer-plan.md)、[发布记录](../../doc/release-0.4.23.md)、本目录 | 记录需求转向、逐文件复核和构建/验证材料，暂不提交推送。 |

按用户最新要求，仅编译打包供测试，未 git add、commit 或 push。之前只 fetch 核对远程；没有新增 LFS 规则。当前为纯展示变化，不修改清理候选、默认选择、执行、提醒或扫描目录，不新增依赖，不新增复述样式的单元测试。根目录无 AGENTS.md 或 .trae/rules/project_rules.md。

方案反思与评分：在共享内容外设置页面背景 98；共享不透明系统底色 100；容量复用原数据源 100；删除旧指标辅助函数 100，均实施。容量状态随现有激活、扫描、清理及废纸篓操作刷新，无新增定时器。

最终验证完成。[中断构建](interrupted-0.4.21.log)在核心编译阶段收到 SIGINT 后退出 130，未产出中间交付包；[正式构建](package.log)使用下一版本。最终结果如下。

0.4.22 中间包已有 311 项完整测试及包验证通过，日志以 -0.4.22 后缀保留。用户指出材质随桌面透色而不同，隔离的 SidebarMaterialProbe 也复现；最终删除原生材质桥接，改为共享不透明底色，并补磁盘图标标题和右侧计时。最终构建仅调整 UI，未重复 XCTest，仍执行 Core 契约与新包所有自检；验证事实以最终日志为准。

## 最终验收

- 0.4.23（137）[正式构建](package.log)通过 Core 契约、1272 条中英消息检查和固定证书签名。完整 311 项 XCTest 已在同批 0.4.22 通过，最后纯 UI 调整未重复；[最终包自检](verification.log)全部通过，包含 SDK 27.2 / 最低系统 13.0 记录一致性及原有执行安全回归。
- [镜像创建](dmg.log)通过；首次 [资源忙记录](dmg-busy.log)保留，待应用验证结束后顺序重试成功，未改变源码或版本。 [安装核对](installation.log)及[产物摘要](artifact-check.json)确认 App/Helper 版本、严格签名、Automation entitlement、三个执行文件 SHA-256 在构建/安装/挂载镜像中一致。
- 原生普通窗口及全屏的菜单侧栏和首页底栏使用同一浅底，无之前桌面透色造成的左右色差。左下出现硬盘图标和 Disk Space、容量条及可用空间，首页无磁盘卡；Elapsed 与 Scan 按钮同行并垂直居中。六模块、累计清理及空/就绪底栏正常显示。观察时其它只读扫描仍进行中，不将其误称为本批全扫描完成。
- 本轮没有切换系统深色设置，深色采用同一系统颜色源自动适配，不宣称已完成深色截图验收。保留最新应用在清理中心供用户继续测试，未执行真实清理、清空废纸篓、权限修改或 Helper 注册。
- [最终审计](final-audit.log)核对版本打包不再递增、现行文档链接和 diff 检查、真实项目扫描配置未变、HEAD 未变且无暂存内容。清理本轮隔离 App 和安装备份，保留中间测试镜像与日志供对比；未提交、未推送。
