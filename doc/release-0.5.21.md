# 0.5.21（166）

- 大文件范围选项改为左侧 All Large Files、右侧 Duplicate Large Files，默认按目录展示。
- Recommended Cleanup 置顶，目录以完整路径为标题，下一层平铺组内文件。
- 根据共同路径结构比较合并、拆分和混合分组，不设组数、目标文件数量或目录深度限制；独立 Home 分支保持分开，单链压缩、稀疏兄弟合并。
- 搜索保留组归属，手动勾选不改变推荐分类；原选择、保护、项目产物去重和清理流程保持。

Debug 与 Release 均通过 356 Core + 20 App 测试，真实扫描与选择联测通过。详细算法、逐文件理由和验证见 [目录分组说明](large-file-directory-groups.md)。

[应用](../build/SuperCleaner.app) · [安装包](../build/SuperCleaner-0.5.21.dmg)

最终应用结构、稳定签名、启动及清理流程自检通过；包内实际扫描联测通过。安装包已只读挂载核对版本与严格签名后卸载。没有安装替换或执行用户真实删除。
