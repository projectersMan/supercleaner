# 支付宝买断与商业发布实施计划

> **For agentic workers:** 按任务实施，安全与资金路径先写失败测试，再实现和验证。Git操作遵循用户明确指令；本轮已授权提交全部本地改动到远程 feat/marketing，本地保留 codex/alipay-buyout。

**Goal:** 完成 Developer ID、公证、支付宝买断与设备授权的可验证商业交付。

**Architecture:** Swift 原生客户端、Node 原生支付授权服务、既有 DMG/Sparkle 发布链路。

**Tech Stack:** Swift 6 / macOS 13 / CryptoKit / Security；Node.js 24.13+ / node:sqlite / node:crypto。

**Spec:** [设计](commercial-launch-design.md)。

## Global Constraints

- 所有 import 位于文件头，无嵌套函数或 lambda 定义；无动态安装、无默认生产业务参数、无隐藏异常。
- 测试素材与日志在根目录 Tests；用户所指 .trae/rules/project_rules.md 实际不存在，遵循用户给定规范和 doc/development.md。
- 现有删除的 build/SuperCleaner-0.5.10.dmg 属于用户原有改动，不恢复或覆盖。
- 正式发布依赖真实账号、密钥、域名；缺少即明确失败，禁止伪造成功标记。

## Review Focus

1. 支付成功乱序重放不能恢复退款后权益。
2. 离线缓存不能在公钥、产品、设备或时钟不匹配时放行。
3. 设备限制须在并发事务下成立，解绑后旧缓存的最长有效期须明确。
4. 恢复不因未付费、退款或网络故障被阻断。
5. 公证超时不重提同一任务；只在最终 Accepted 后生成可发布产物。

## Task 1：支付与授权服务

**Files:** CommerceService/*.mjs、CommerceService/config.example.json；Tests/commercial-launch/*.test.mjs。
**Interfaces:** 实现设计固定接口和 SignedLicense 协议；不修改 Swift 文件。

- [x] 写并运行失败测试：RSA2、金额/商户、重复/乱序通知、设备上限、刷新/解绑/撤销。
- [x] 实现服务端配置、订单与授权事务、签名、网页支付、接口、管理核对、部署材料。
- [x] `node --test Tests/commercial-launch/*.test.mjs` 全部通过；最终58项，测试使用真实临时 RSA/Ed25519 密钥及 SQLite，规则使用真实Swift回读。

## Task 2：Swift 授权核心与执行边界

**Files:** Sources/CleanerCore/LicenseStore.swift、CommercialConfiguration.swift、CleanupExecutionCoordinator.swift；相关现有调用/契约测试。
**Interfaces:** 使用设计中的 Claims/SignedLicense；商业配置独立资源；新清理检查必需依赖，不给生产绕过默认值。

- [x] 为租约、篡改、产品/设备、回拨、无授权清理及安全恢复写失败检查。
- [x] 实现核心策略，更新旧 trial 契约和全部 coordinator 构造调用；AppInfrastructure 留给集成任务。
- [x] 编译并运行 CoreContractChecks 和可用 XCTest；352项Swift测试通过，商业/Helper/执行/跨语言契约通过。

## Task 3：App 与 Helper 接线

**Files:** Sources/CleanerApp/Commercial*.swift、AppInfrastructure.swift、AppModel.swift、设置页面、Helper 协议/处理器及本地化。
**Interfaces:** 按固定 HTTP 协议；Keychain 保存凭证；闭包授权检查注入 coordinator。

- [x] 验证未授权扫描/清理、购买后激活、断网刷新、设备解绑和恢复保留；使用明确标注的本地服务夹具。
- [x] 实现原生买断设置、购买与轮询、激活、刷新、设备管理，贯通公共执行与 Helper。
- [x] 编译真实 App/Helper；Debug/Release AppModel自检、客户端URLSession/设置模型语义、跨语言验签通过。正式签名包的真实Keychain及干净Mac交互仍在外部验收项。

## Task 4：签名、公证与部署

**Files:** Scripts 发布脚本及商业配置打包检查；Tests/commercial-launch 发布检查。

- [x] 完善预检，明确缺少证书、商业/发布配置、公证凭据时拒绝；修复原发布链路缺口。
- [x] 补齐现有生产规则包签名工具，28项真实Swift回读通过；生产规则和密钥仍待配置。
- [ ] 用户配置证书/公证凭据后，正式构建、签名并提交 Apple；跟踪同一 submissionID 至终态。
- [ ] Accepted 后为 App 和 DMG 装订/验证票据，检查签名、镜像及 Gatekeeper。
- [ ] 使用用户提供的生产环境部署 HTTPS 服务，真实支付宝沙箱/生产购买、激活、换机、退款验证。

## Task 5：审计与交付

- [x] 更新 README.md、doc/architecture.md、doc/development.md、商业上线使用文档及旧正式发布检查清单。
- [x] 逐文件 git diff，记录必要性、测试证据、真实完成/待办；独立安全审查后修复重要发现。
- [ ] 目标验收矩阵全部有直接证据后，方可标记目标完成。
