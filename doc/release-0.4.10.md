# 0.4.10（124）本地交付

Settings 新增 Project Scan Folders：三行高的内部滚动列表展示全部目录，支持原生面板多选添加、逐项移除、保存与撤销。移除只改变扫描范围；草稿不保存不写配置。复用原 ProjectScanRootsStore，不复制配置源，不写死用户名，不增加全盘或 Git 项目发现策略。

设置无报告时保存供下次扫描使用，有报告时仅刷新 Project Artifacts；项目页原选择入口没有报告时仍走权限准备。配置失败在设置和无报告项目页都可见；保存期间阻止新扫描、权限继续、模块续跑与清理。取消刷新后旧范围项目结果不可执行，执行层仍读取最新根目录复验。

版本从 0.4.9（123）递增一次。[固定证书构建](../Tests/project-scan-roots-settings/package.log)通过 305 项 Release 测试、核心契约和 1273 条双语检查；[包自检](../Tests/project-scan-roots-settings/verification.log)、[DMG创建与挂载检查](../Tests/project-scan-roots-settings/dmg.log)和[安装核对](../Tests/project-scan-roots-settings/installation.log)通过。App/Helper 均为 0.4.10（124），严格签名、既有 entitlement 与三个可执行文件核对一致。

原生普通与系统窄窗口均确认三行视口和完整操作按钮；内部滚动可查看末尾，11→10 草稿移除后撤销回 11。面板多选两个目录后草稿为 13，撤销回 11，取消面板不改变草稿。期间界面工具短暂断连，进程采样无卡死证据，经 Finder 重开窗口后恢复并完成全部验收，无额外代码修改。真实配置文件仍未生成，未更改用户实际范围；窗口尺寸已恢复，安装版最终留在空闲清理中心。逐文件复核见 [验证记录](../Tests/project-scan-roots-settings/README.md)。

产物为 [SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.10.dmg](../build/SuperCleaner-0.4.10.dmg)，本机安装副本为 `/Applications/SuperCleaner.app`。没有执行真实清理、清空废纸篓、提交或推送；本地验证不代表公证验收。
