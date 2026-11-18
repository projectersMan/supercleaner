# 0.4.14（128）本地交付

版本递增已写入 build-app.sh：基础签名/资源/SDK检查通过后、首次 Swift 编译前调用一次 version.py next-build，自动增加 patch 与构建号，打印并保存实际值，再供 App/Helper 打包共用。每次重新编译也会递增，无需手动 bump；普通测试、单独验证、DMG 与发布不递增。已进入编译后的失败号码不回滚，下次运行分配新号码。

next-build 复用现有校验和原子保存；CI展示版本须等于下一patch，CI构建号须大于旧号并写回配置。无效参数在写入前拒绝。旧的按修改批次手动递增说明已同步替换，历史交付记录保持原样。

本次没有先手动 bump，直接运行编译脚本，日志记录自动从 0.4.13（127）到 0.4.14（128）。11 项版本测试、实际无效 CI 构建号预检、305 项 Release 测试、1271 条双语检查与核心契约通过；独立只读复查通过。后续 verify、DMG、安装和挂载核对均未改变 Version.json，前后快照与 App/Helper 元数据一致。

固定证书包验证、DMG签名及挂载检查通过。App、Helper 与 DMG 中元数据均为 0.4.14（128），安装版及镜像中的三个可执行文件与构建一致，严格签名和既有 entitlement 保留。原生设置页确认 App version 0.4.14、Build 128，最终回到空闲清理中心，未扫描或执行清理、清空废纸篓、权限或 Helper 注册。

产物：[SuperCleaner.app](../build/SuperCleaner.app)、[SuperCleaner-0.4.14.dmg](../build/SuperCleaner-0.4.14.dmg)，本机 `/Applications/SuperCleaner.app` 已更新。逐文件说明、版本快照及日志见 [验证记录](../Tests/build-auto-version/README.md)。未提交或推送；本地检查不代表公证验收。
