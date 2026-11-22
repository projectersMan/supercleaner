# 0.5.27（172）

重复大文件页面新增与 Local AI Models 一致的“全选”三态控件。它只选择当前搜索、All/Duplicate 范围内，且通过可读性、保护和风险检查的文件；再次点击会取消同一范围，隐藏项和范围外已有选择不会被清除。目录组勾选、折叠/展开和右键批量控制保持不变。

应用自检、真实合成扫描联测和 App 测试 22/22 通过。Core 全量测试中既有 `DeletionCancellationTests.testTwoLargeFilesStageTiming` 时序测试仍单独复现失败，本轮没有修改 Core 执行代码。

[目录控件说明](large-file-directory-controls.md) · [大文件分组说明](large-file-directory-groups.md)
