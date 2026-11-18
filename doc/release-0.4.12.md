# 0.4.12（126）本地交付

清理中心模块行内统计前缀由 Default 改为 Cleanup/清理。Project Artifacts 和 Local AI Models 每次本模块成功扫描后优先显示 Cleanable，并勾选具备清理资格的项目；没有可清理项时显示 All。用户之后取消的勾选和筛选会跨导航、无关模块发布、最终整批汇总保留；本模块重新扫描成功才重新应用默认，搜索与排序保留。

预选复用现有保护、活动和不完整过滤，不改 Core 候选风险与显式选择标记。删除继续要求确认与执行前复验；两个资源模块仍不进入首页全部默认清理队列。模型页同步预选说明，不再显示“默认保留”。

版本从 0.4.11（125）递增一次。305 项 Release 测试、1271 条双语检查、核心契约、固定证书包验证和 DMG 挂载/签名检查通过。App/Helper 同为 0.4.12（126），安装副本严格签名、既有 entitlement 与三个可执行文件均与构建一致。独立复查未发现确定缺陷，另补充旧报告 baseline 的新 generation 渐进回归通过。

原生只读扫描确认项目页默认 Cleanable，4 个可清理项约 4.41 GB 自动勾选；取消 target 后剩 3 项，切换模型页再回来仍未复选。模型页当次 4 项均因活动未知/运行受保护，正确默认 All 且零勾选。没有执行真实清理、清空废纸篓、权限或 Helper 注册，真实项目目录配置指纹保持一致。

产物：[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.12.dmg](../build/SuperCleaner-0.4.12.dmg)，本机 `/Applications/SuperCleaner.app` 已更新。完整逐文件说明、最终页面状态与验证证据见 [验证记录](../Tests/resource-cleanable-defaults/README.md)。未提交或推送；本地验证不代表公证验收。

本批只读界面检查后正常退出未完成的系统/Agent 扫描，重开最终安装版留在空闲首页；没有把该次只读检查记作整盘或全模块扫描完成。行内 Cleanup 前缀已核对安装版双语资源与界面调用。
