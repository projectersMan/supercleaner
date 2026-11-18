# 0.4.24（138）

Project Artifacts 移除 Cleanable，保留 All / Protected / Selected，初始有选项默认 Selected，否则 All。Settings 增加项目编译产物默认勾选开关，初始关闭；开启后自动勾选通过检查的项目产物，包括 Git 跟踪项。关闭保留人工选择，首页默认清理排除项目。Git 跟踪产物可手选，其它保护继续生效。模型保持原有分类且始终手选。

[逐文件修改与验证](../Tests/project-selection-preferences/README.md)。本轮只编译打包供测试，未提交、未推送。315 项 XCTest、核心契约、正式包自检、固定签名及镜像安装一致性检查通过；原生界面已验证开关默认关闭、三项范围、Git 跟踪 DMG 手选及首页队列排除。
