# 目录展开与批量勾选

日期：2026-11-22。

目录组和 Recommended Cleanup 默认展开。点击标题或箭头展开/折叠；勾选框是独立的原生三态控件，不触发折叠。右键任意目录组标题可直接使用“全部展开”和“全部折叠”，顶部不再放置重复控制，保持筛选栏简洁。折叠状态按组 ID 保存在当前页面，搜索暂时隐藏组、切换排序或范围不会清空；页面重新创建后恢复默认展开。折叠不改变文件选择。

未选或部分选中时点击补齐全选，全选时取消。只操作该组当前显示、可读且保护规则允许选择的文件，允许纳入手动选择项；不选中目录本身，不修改聚类。搜索隐藏项、推荐组与其他路径组保持原选择。当前模块扫描、清理执行或应用更新期间禁用组选择；没有可选文件时禁用复选框。

筛选栏右侧新增与 Local AI Models 一致的“全选”三态控件。它只作用于当前搜索词、All/Duplicate 范围和当前扫描树中可读且可选择的文件；受保护、不可读、目录节点以及被搜索隐藏的项目不会被加入。部分选择时点击补齐当前范围，全选时再次点击取消当前范围，范围外已有选择保持不变。筛选栏只保留一处“可选项 / 当前范围总项”计数，不再重复显示总文件数；切换范围、排序或搜索后状态实时更新，扫描、清理和更新期间控件禁用。

## 逐文件复核

| 文件 | 修改与原因 |
| --- | --- |
| [DiskSpaceView.swift](../Sources/CleanerApp/DiskSpaceView.swift) | 以组 ID 保存折叠状态，组头增加独立展开按钮和三态勾选框，内容按展开状态显示；右键组标题提供全部展开/折叠。 |
| [ResourceCleanupView.swift](../Sources/CleanerApp/ResourceCleanupView.swift) | 已有原生三态复选框改为模块内复用，避免新增另一套状态或鼠标行为。 |
| [LargeFileDirectorySection.swift](../Sources/CleanerApp/LargeFileDirectorySection.swift) | 从当前组节点筛选可读文件，与最新可选候选取交集，排除保护项、目录和组外项。 |
| [AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 当前 All/Duplicate 范围解析候选，校验忙碌状态后复用原批量选择入口；扩展真实扫描自检验证全选、取消、部分选择、搜索隐藏保留和手动组。 |
| [DiskSpaceView.swift](../Sources/CleanerApp/DiskSpaceView.swift) | 在宽/窄筛选栏布局中复用 Local AI Models 的全选摘要，显示三态选择与可选项/总项计数。 |
| [LargeFileDirectorySectionTests.swift](../Tests/CleanerAppTests/LargeFileDirectorySectionTests.swift) | 增加保护、不可读、组外文件的批量选择边界测试。 |
| [测试记录](../Tests/large-file-directory-controls/README.md) | 记录全量测试、真实扫描、构建及包内验证。复用已有合成素材脚本，测试结束清理生成文件。 |
| README、doc/docs 架构与开发文档、[分组说明](large-file-directory-groups.md) | 同步用户操作、作用范围与验证要求。 |
| [Version.json](../Version.json)、发布说明 | 标准构建递增版本，区分含目录控件的新包。 |

## 自审

- 局部 97/100：折叠和选择采用独立控件，避免点勾选框时误折叠，已实施。
- 局部 98/100：三态与可选子项一致，部分选中补齐、全选取消，已实施并联测。
- 局部 96/100：全选与搜索、All/Duplicate 范围共用同一可见候选解析，避免出现“勾选了但列表不可见”的错觉，已实施。
- 全局 100/100：按当前可见文件和最新候选取交集，复用既有选择与保护流程，已实施并回归。
- 全局 95/100：搜索和其他组选择互不干扰，已覆盖实际扫描联测。

没有新增依赖，不创建 requirements.txt。项目为 Swift，`.trae/rules/project_rules.md` 不存在。既有未提交修改保持，不提交代码、不执行用户真实清理。

## 验证结果

Debug 与 Release 的 App 测试 22/22 通过；本轮 Core 全量首轮有既有 `DeletionCancellationTests.testTwoLargeFilesStageTiming` 时序失败，单独重跑仍复现，未触及 Core 代码。合成文件的真实扫描联测覆盖页面全选、全部取消、部分状态补齐、搜索隐藏项保留、手动文件组选择及其他组不受影响。独立只读复核确认全选范围、复选框和展开按钮事件分离、可选边界与页面内折叠状态正确。

逐项 diff 已复核：本轮新增行为仅为分组展示控制与文件批量选择，未更改目录聚类、删除算法或保护范围。详细日志位于 [Tests/large-file-directory-controls](../Tests/large-file-directory-controls)。

0.5.22（167）应用结构、稳定签名、启动和既有清理自检通过，最终包内真实扫描与目录批量选择联测通过。发布入口见 [0.5.22](release-0.5.22.md)。

0.5.24（169）在目录组标题的右键菜单增加“全部展开”和“全部折叠”，与顶部控制共用当前组状态。Debug、Release 各通过 356 Core + 22 App 测试，应用自检和 DMG 只读版本/签名核对通过。发布入口见 [0.5.24](release-0.5.24.md)。

0.5.25（170）移除顶部重复控制，只保留目录组标题右键菜单作为全部展开/折叠入口；单组箭头仍可操作。Debug、Release 各通过 356 Core + 22 App 测试，应用自检和 DMG 只读版本/签名核对通过。发布入口见 [0.5.25](release-0.5.25.md)。

0.5.27（172）在重复大文件筛选栏加入与 Local AI Models 一致的当前范围全选/取消全选三态控件，范围由搜索、All/Duplicate 和可读可选文件共同决定；目录组勾选、保护和清理门禁保持不变。应用自检通过，App 测试 22/22 通过；Core 的既有大文件时序测试仍单独复现环境失败，未由本轮修改引入。

0.5.28（173）移除筛选栏右侧重复的总文件数，只保留全选控件旁的可选项/当前范围总项计数，宽窗口和窄窗口布局保持一致。App 定向测试、Core 合约、自检和 DMG 只读签名核对通过。

DMG 已只读挂载核对 0.5.22（167）与严格签名，通过后卸载。合成测试 home 和打包临时目录已清理。未替换用户已安装应用或执行真实删除。
