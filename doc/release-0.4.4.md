# 0.4.4（118）本地交付

本批增加与 Agent 环境并列的“本地 AI 模型”和“项目产物”，形成六个独立清理维度；两个新维度均需手动选择，复用现有确认、实时安全复验、回执和恢复。项目按源码工程分组，支持选择多个扫描根并单独重扫。清理中心显示 Home 所在卷总容量、已用与可用，读取失败明确显示错误，不把累计逻辑清理量等同于物理释放量。

独立用户 CLI 已移除，保留 CleanerCore、CleanerHelper、AgentInference 与直接 Core 契约验证；本批无新增依赖，最低系统仍为 macOS 13。

- [Version.json](../Version.json) 从 0.4.3（117）递增一次；App 与 Helper 同为 0.4.4（118）。
- 完整 Release XCTest 295 项、0 失败，核心契约与 1229 条双语资源检查通过，见 [构建日志](../Tests/local-ai-projects-disk/package.log)。
- [SuperCleaner.app](../build/SuperCleaner.app) 使用既有固定证书签名，[完整包验证](../Tests/local-ai-projects-disk/verification.log) 通过。
- [SuperCleaner-0.4.4.dmg](../build/SuperCleaner-0.4.4.dmg) 生成、挂载、Applications 拖拽入口、图标及包签名通过，见 [DMG 日志](../Tests/local-ai-projects-disk/dmg.log)。首轮系统“资源忙”后原脚本重试成功。
- 安装副本 `/Applications/SuperCleaner.app` 已替换并成功打开；版本、签名及三个可执行文件与构建产物一致，见 [安装检查](../Tests/local-ai-projects-disk/installation.log)。没有替换应用数据或偏好目录。
- 原生界面确认六入口、真实容量和项目目录选择弹窗。取消弹窗后自动化连接持续超时，进程采样显示正常事件循环；目录提交后的实机流程未标为通过。模型/项目 Core 真实夹具、AppModel 刷新/取消和执行安全回归均通过。完整边界、两项审查修复及逐文件原因见 [验证审计](../Tests/local-ai-projects-disk/README.md)。

未执行真实用户文件清理，未清空废纸篓，未注册 Helper，未提交或推送。本地证书与包验证不代表 Developer ID、公证或线上发布验收。
