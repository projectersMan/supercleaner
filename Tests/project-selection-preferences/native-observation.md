# 原生界面观察（已安装 0.4.24 / 138）

- Settings 显示版本 0.4.24 / 138，项目开关为 off，英文标签和两行说明完整；扫描目录仍为原 11 个，三行滚动窗口保留，没有保存或编辑目录。
- 启动一次只读全扫描；Settings 开关立即 disabled，仍 off。没有修改权限或 Helper。
- 项目结果发布后共 38 项；只有 All / Protected / Selected 三项范围，All 初始选中，Select All 为 0，底栏 No cleanup items selected。
- .build/checkouts/Sparkle/Tests/Resources/SparkleTestCodeSignApp.enc.dmg 复选框启用且初始为 0。手动勾选后为 1，Selected 显示 1 / 38，底栏 1 items selected / 约 1.8 MB；仅改变计划选择，没有点击 Confirm Deletion。
- 回首页 Project Artifacts 已完成但没有 Cleanup 数量，默认队列不包含该手选 DMG，符合关闭设置的规则。
- 返回项目页使用 Clear Selection，确认 0 / 38；再恢复 All，38 / 38 且所有勾选清空，供用户继续测试。活动或无法确认的构建目录仍 disabled。
- 未开启真实预选开关；on/off 与持久化、人工决定保留由隔离 UserDefaults 的正式包自检覆盖。
- 观察结束时系统/应用/Agent 只读扫描仍进行，不宣称本批实时六模块扫描全部结束。未执行真实清理、废纸篓清空、权限修改或 Helper 注册。
