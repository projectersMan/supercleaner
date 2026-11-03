# 0.2.34（67）最终交付核对

- CleanerApp、CleanerHelper、supercleaner release编译通过；最新布局改动后重新编译CleanerApp通过，未运行测试套件。
- 1015条双语校验、git diff --check和签名完整性通过。
- 最终build、/Applications/SuperCleaner.app及DMG中App的123个文件/符号链接一致；App/Helper均0.2.34（67）。
- DMG SHA-256：a8dd697970a4a758cdd6da290de16384946632b3c68fe684c4acb80ca16ff4b6。
- 用户重新授权后，在最终同一安装包实机完成扫描和以下验收：
  - 默认1280 pt窗口与238 pt侧栏，四项范围94/22/10/65应用切换时搜索框两端均约516–1032 px；分段、排序和计数均固定。工具条约306–390 px，与同包大文件页一致，无Refresh Apps。
  - 系统较窄窗口下两行无重叠，搜索框仍固定260 pt，切换范围不改变几何；核对后恢复原窗口尺寸、238 pt侧栏及可卸载筛选。
  - 1026个Skill、45份MCP配置；Skill三个比例右对齐，MCP首行长名称旁100.0%完整可见，当前对象元数据紧随左栏描述，两栏顶部对齐且无Combined Coverage。
- 当前App保留有效授权与扫描结果，验收后未再修改二进制、重打包或重启。
- 先前共享源User/Shared、缓存预选、Trae中archify独立条目和Codex685项已实机核对；右侧引用均来自当前清单。仅进行只读扫描/查看，没有实际删除。
- 临时视频帧、采样脚本/日志、备份App/旧DMG、临时目录和镜像挂载已清理；仅保留交付记录。未提交或推送。
