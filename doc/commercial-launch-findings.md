# 商业上线调查

- 2026-11-21：仓库 Swift 6/macOS 13，Sparkle 2.10.0；已有 LicenseStore 签名雏形，但未接 App 或执行器，仅有过期 trial 契约。
- 已有 Scripts/check-production-signing.sh、publish-release.sh 和公开发布配置；配置示例仍为占位，README 声明当前本地包非 Apple 公证版本。
- 沙盒内 `security find-identity` 返回 0 个身份；经授权在沙盒外只读复核发现两个本地开发身份，均不是 Developer ID。notarytool 1.1.4 可用，尚无可用 Developer ID 私钥或公证 Profile 的证据。
- Node v25.8.1 可用且 node:sqlite 可加载；服务使用 Node 24.13+ 标准库，无需新增包或 Python 环境。
- 根目录 .trae、AGENTS.md 不存在。原有工作区仅有已跟踪旧 DMG 删除。
- 已向用户询问 Apple 资质、支付宝权限、售价/设备数/部署环境；不索取聊天中的密钥或密码。
- 用户已确认暂定售价 9.99 元（999 分）、每份两台 Mac；尚未加入 Apple 开发者计划，只有个人支付宝，无域名/服务器/网站。已追问经营主体和 7 天/30 天离线期限。
- 初始 SwiftPM 编译遇沙盒外 ModuleCache 不可写，改为项目内 CLANG_MODULE_CACHE_PATH；后因网络受限不能下载固定 Sparkle，已经申请授权后继续同一编译任务。
- 公证辅助脚本测试真实运行通过三项：Accepted 后恢复不再上传、内容变化拒绝、上传结果不确定拒绝重提；测试使用模拟 Apple CLI，不代表真实 Apple 接受。
- Sites 支持公开匿名请求、Worker 和 D1，但当前实现采用原生 Node SQLite；迁移会引入额外运行时和存储适配，暂不为了未取得的支付权限建立第二套后端。先准备可部署服务与反向代理材料，实际托管待明确。
- 最终采用原生Node服务+systemd+Nginx部署材料，没有创建Sites项目或购买托管。用户已确认可签约经营主体和7天租约；待提供云平台账号、预算和生产域名。
- 当前真实发行门禁仍拒绝缺少正式配置和Apple身份，商户配置样例仍拒绝缺少publicBaseURL；未创建真实公证submission或实际支付宝订单。
- 根agent最终证据、环境限制及明确未完成项见 [验收矩阵](commercial-launch-acceptance.md)，逐文件保留原因和建议评分见 [修改复核](commercial-launch-change-review.md)。
- 官方参考：Apple Developer ID https://developer.apple.com/help/account/certificates/create-developer-id-certificates ；公证 https://developer.apple.com/documentation/security/customizing-the-notarization-workflow ；支付宝异步通知 https://developer.alibaba.com/docs/doc.htm?articleId=105902&docType=1&treeId=193 。
