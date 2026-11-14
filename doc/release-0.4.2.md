# 0.4.2（116）重新编译与打包

## 原因与范围

已核对提交 `bb7e07a` 的 [应用筛选](../Sources/CleanerCore/ApplicationListFilter.swift)：Uninstallable 原本包含 `!isRunning` 条件。本次对话中将其去掉，是修改造成的回归，并非原设计要求。现已恢复未运行条件，并保留 Running 排除系统应用、第三方权限判断和输入法识别修复。

分类保持互斥：系统应用 → Protected；其余应用正在运行 → Running，未运行 → Uninstallable；All 为完整汇总。上一轮实机已验证 84 + 10 + 21 = 115，Chrome 在 Uninstallable 为 0、Running 为 1。

本次使用现有 [版本脚本](../Scripts/version.py) 将 [Version.json](../Version.json) 从 0.4.1（115）递增到 0.4.2（116），只递增一次；构建与打包使用既有脚本和固定签名证书。

## 产物与验证结果

- [x] [App](../build/SuperCleaner.app)：固定证书重新编译、签名，App 与 Helper 均为 0.4.2（116）。
- [x] [DMG](../build/SuperCleaner-0.4.2.dmg)：包含同一 App、Applications 快捷方式及应用图标，挂载后版本、签名与文件内容均通过复核。
- [x] `/Applications/SuperCleaner.app`：已更新安装副本，设置页确认显示 0.4.2（116），完全磁盘访问仍可用。
- [x] 核心契约、261 项 Release 测试、打包验证脚本、DMG 完整性及逐处 diff 检查通过。

本批验证日志放在 [Tests/application-uninstall-eligibility/release-0.4.2](../Tests/application-uninstall-eligibility/release-0.4.2)。

DMG 大小为 301,793,795 字节，SHA-256 为 `ec1c2626eb3e53a11b66f9dc0cde0fe2d3d72ed52e2712cb200043ea6c15e3bd`。App、DMG 内 App、安装副本的文件内容与软链接一致，三者深层签名校验通过；镜像已卸载。详细结果见 [verification.txt](../Tests/application-uninstall-eligibility/release-0.4.2/verification.txt)。

## 逐文件原因与自审

- `Version.json`：版本和构建号同步递增，解决此前代码已更新但包版本仍为 0.4.1 的识别问题。
- `README.md`：更新面向用户的本地 App/DMG 入口和版本。
- `doc/application-uninstall-eligibility-plan.md`、本文、架构与开发入口：记录已核实的回归来源、打包步骤和验收结果。
- 验证目录：保存本轮版本、签名、DMG、安装副本和校验记录；此前分类代码保持已验收的互斥规则。

局部建议：统一版本与构建号 100 分；全局建议：App、Helper、DMG 和安装副本一致性验证 99 分，均实施。无新增依赖，不需要变更 `requirements.txt`；不提交、推送或远程发布。
