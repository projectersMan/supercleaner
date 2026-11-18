# 头部三列边界对齐验证

基于 0.4.7（121），按用户红线将覆盖说明、安全卡与操作行放入同一水平边界：左侧对齐标题文字/扫描按钮，右侧对齐废纸篓按钮边缘；上下均为 12pt 列间距。将首末列的独立边距移到公共容器，去掉废纸篓按钮多余的外边距，保留原生控件尺寸与功能。

| 文件 | 修改原因 |
| --- | --- |
| [DashboardView.swift](../../Sources/CleanerApp/DashboardView.swift) | 公共容器统一左 52pt/右 24pt 边界，说明卡和操作行共享列间距，避免上下两行独立分配宽度造成错位。 |
| [Version.json](../../Version.json) | 本批一次递增为 0.4.8（122），App/Helper 同步。 |
| [README.md](../../README.md) | 同步用户可见的对齐布局及实际安装入口。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 记录公共边界与列间距。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md) | 明确整组设置边距，避免后续重新在首末列重复添加。 |
| [实施计划](../../doc/dashboard-all-default-plan.md)、[发布记录](../../doc/release-0.4.8.md)与本目录 | 保留本批范围、评分及构建/原生核验事实，既有批次记录保留。 |

局部建议整组共享边距 100 分，全局建议上下共享列间距与边界 98 分，均实施。本批为可逆样式调整，不新增复述布局的测试、组件或依赖；项目为 Swift，无需 requirements.txt。根目录无 AGENTS.md 或 .trae/rules/project_rules.md。既有改动保留，不提交或推送。

## 实际结果

- 语法解析与 `git diff --check` 通过；[固定证书构建](package.log)完整执行 305 项 Release 测试、0 失败，核心契约和 1259 条双语资源检查通过。
- [完整包验证](verification.log)及 [DMG 创建、挂载、签名检查](dmg.log)通过；[安装核对](installation.log)确认 App/Helper 版本一致、严格签名和既有 entitlement 正确，三个可执行文件与构建一致。
- 原生英语截图确认：说明卡左边缘、扫描按钮和标题文字共享左边界；最右卡片和废纸篓按钮共享右边界；中间卡片与磁盘容量列起点对齐。覆盖说明也使用共同边界，六个模块行完整可见，长说明保留 tooltip。
- 旧版空闲时正常退出后更新 `/Applications/SuperCleaner.app`，最终版重开并留在空闲首页。未触发扫描或清理、清空废纸篓、权限授予或 Helper 注册，应用数据和偏好目录保留。
- 已清理本批旧安装备份和包自检夹具，逐文件核对均为必要修改；详见 [最终审计](final-audit.log)。未提交或推送。
