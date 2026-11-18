# 0.4.8（122）本地交付

按用户红线统一清理中心头部边界：覆盖说明、安全卡和操作行使用同一外边距；左侧对齐标题文字与扫描按钮，右侧对齐废纸篓按钮边缘。上下三列共用 12pt 间距，移除首末列及按钮多余的独立外边距。扫描、默认清理和废纸篓行为保持原样。

[Version.json](../Version.json) 从 0.4.7（121）递增一次。305 项 Release 测试、0 失败，核心契约、1259 条双语检查、完整包验证和 DMG 检查通过；原生界面确认左右边界及中间列起点对齐，六行完整可见。逐文件说明与日志见 [验证记录](../Tests/dashboard-column-alignment/README.md)。

[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.8.dmg](../build/SuperCleaner-0.4.8.dmg) 及安装副本 `/Applications/SuperCleaner.app` 已更新；App/Helper 均为 0.4.8（122），签名和可执行文件一致，最终安装版已重新打开。未执行实际清理、清空废纸篓、提交或推送；本地签名和包检查不代表公证或线上发布。
