# 0.4.13（127）本地交付

Agent 显示筛选现在区分自动默认和手动选择：当前 Skill/MCP 类型及平台有已选项时自动 Selected，没有时自动 All；异步预选变化会更新自动默认。用户主动选择 All 或 Selected 后保持其筛选，包括空 Selected。类型切换同步清理可见缓存，过滤前只解析一次默认范围，不改变选择资格、预选或执行策略。

大文件页原本默认 All Large Files，已经符合本次要求，未修改其视图/筛选逻辑；手动选择空的重复文件范围也不会被覆盖。

版本从 0.4.12（126）递增一次。305 项 Release 测试、1271 条双语检查、核心契约、固定证书包验证、DMG挂载与签名检查通过；App/Helper 均为 0.4.13（127），安装版签名、既有 entitlement 和三个可执行文件与构建一致。独立复查未发现确定缺陷或阻塞漏测。

原生只读验证确认大文件默认 All Large Files；Agent 清单元数据就绪但尚无目录级选择时，Skills 和 MCP 均自动 All。手动 Selected 即使为空仍保持，切换类型后保持；手动回 All 恢复清单。验证期间取消本批系统/应用及 Agent 未完成的内容扫描，不将这次元数据检查声称为完整内容扫描；有选择和迟到预选变化由模型夹具覆盖。没有点击清理、清空废纸篓、权限或 Helper 注册，最后正常退出并重开安装版至空闲首页。

产物：[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.13.dmg](../build/SuperCleaner-0.4.13.dmg)，本机 `/Applications/SuperCleaner.app` 已更新。逐文件说明与实际日志见 [验证记录](../Tests/agent-empty-default-scope/README.md)。未提交或推送；本地检查不代表公证验收。
