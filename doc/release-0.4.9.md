# 0.4.9（123）本地交付

- Scan 按钮可见高度从约 28pt 增为 56pt，保留宽度量级、左边界、计时和 Button 语义；专用样式提供按压、禁用和焦点轮廓。
- 修复模型/项目页全选控件只设置无障碍标签、可见标题为空的问题。顶部显示 Select All/全选，计数保留固有宽度，窄窗口继续自动分行；组内仍使用无文字小复选框。
- 共用英文标题统一为 Project Artifacts，覆盖侧栏、页面和首页。

扫描速度问题已核对：两个模块按指定目录与元数据工作、并行发布；本地模型不加载 GB 级权重。旧版本次结果为模型 4 项、项目 8 项，模型页确有运行/活动未知的受限提示；首页现有完成勾选仍兼容 completed/limited 展示，不代表全盘无遗漏。本批未修改扫描范围和安全规则。

[Version.json](../Version.json) 从 0.4.8（122）递增一次。305 项 Release 测试、0 失败，核心契约、1259 条双语检查、完整包验证和 DMG 检查通过；普通与系统窄窗口均原生核验。项目实际全选/清空仅改变可清理项勾选，未执行删除。详见 [逐文件说明与验证日志](../Tests/dashboard-control-sizing/README.md)。

[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.9.dmg](../build/SuperCleaner-0.4.9.dmg) 与安装副本 `/Applications/SuperCleaner.app` 已更新，App/Helper 同为 0.4.9（123），签名和可执行文件一致；原窗口尺寸已恢复，最终安装版重开空闲首页。未执行真实清理、清空废纸篓、提交、推送或线上发布；本地包检查不代表公证验收。
