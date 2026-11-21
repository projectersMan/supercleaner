# 支付宝买断与商业发布设计

## 目标与边界

用户已授权直接实施：Developer ID Application 签名、Apple 公证，以及支付宝一次性买断；不提供月付、年付、试用或自动续费。保持 macOS 13 和现有六维度、文件安全复验及恢复能力。不代办付费账号或购买云资源。初始开发未提交；现按用户追加指令，将本地全部改动提交并推送到远程 feat/marketing，本地继续使用 codex/alipay-buyout。

买断权益永久有效；为支持退款撤销及设备解绑，设备领取有期限的离线授权租约。离线期限、售价、设备数量均为必填生产配置，不硬编码业务默认值。租约失效要求联网刷新，不代表买断到期。首次激活联网；恢复、历史、导出回执、移除 Helper 始终可用。

## 方案与取舍

沿用官网 DMG、Sparkle、现有发布门禁；不改 Mac App Store。支付宝电脑网站支付在系统浏览器完成；服务端创建订单并验证异步通知，客户端不得通过同步跳转自行认定付款。授权服务采用 Node.js 24.13+ 原生 HTTP、SQLite、RSA-SHA256、Ed25519，无第三方运行依赖或动态安装；Swift 使用系统 CryptoKit、Security、URLSession。相比自行部署第三方支付聚合服务，直接接官方支付宝减少中间商和密钥暴露。

GPL v3 保持不变；收费不自动改变许可证。闭源或限制 GPL 既有权利不在此次授权内，正式销售说明应明确官方分发与服务的范围。

## 固定接口协议

所有业务 API 使用 POST、JSON、camelCase；生产仅 HTTPS。金额由服务端配置的整数分生成，客户端不能指定金额。时间是 Unix 秒整数，UUID 为标准字符串。响应错误为 `{"error":"可展示的错误"}`，不输出密钥。

- `POST /v1/orders`：`{email,deviceID}` → `{orderID,pollToken,checkoutURL}`。订单随机且 pollToken 至少 256 bit，仅保存其哈希。
- `GET /checkout/<orderID>?token=<pollToken>`：展示订单及支付宝跳转，设置 no-store、no-referrer、CSP；禁止第三方资源。
- `POST /v1/orders/status`：`{orderID,pollToken}` → `{status,licenseKey}`，未付款 licenseKey 为 null；状态 pending/paid/revoked/closed。仅原购买凭证可领取激活码。
- `POST /v1/alipay/notify`：form-urlencoded。验证 RSA2 签名，app_id、seller_id、out_trade_no、total_amount、trade_no、交易状态；幂等处理并禁止撤销后被旧成功通知重新激活。退款通知及管理撤销持久化；退款查询/人工对账不依赖前端跳转。
- `POST /v1/licenses/activate`：`{email,licenseKey,deviceID,deviceName}` → SignedLicense。同设备重复激活幂等，设备上限在事务中检查。
- `POST /v1/licenses/refresh`：同上 → SignedLicense。只允许已激活且未撤销的设备，不自动重新激活解绑设备。
- `POST /v1/licenses/devices`：`{email,licenseKey}` → `{devices:[{deviceID,deviceName,activatedAt}]}`。
- `POST /v1/licenses/deactivate`：`{email,licenseKey,deviceID}` → `{deactivated:true}`，重复解绑幂等。
- 管理工具仅在服务器命令行运行，支持退款后撤销、支付状态核对及备份，不开放无鉴权管理接口。

`SignedLicense = {claimsData:base64(JSON UTF-8),signature:base64(Ed25519签名)}`；签名原文不可重新序列化。

`LicenseClaims = {licenseID:UUID,productID:string,email:string,deviceID:UUID,issuedAt:Unix秒,offlineValidUntil:Unix秒,capabilities:[standardScan,agentScan,newCleanup]}`。

客户端验证签名、productID、deviceID、签发时间及离线期限；Keychain 保存设备 UUID、激活信息、授权凭证和最后可信时间，检测明显时钟回拨。私钥只在服务器。客户端不存支付宝私钥或管理凭据。

## 执行接线

复用并升级 CleanerCore/LicenseStore.swift，去除旧 trial 模型。`CleanupExecutionCoordinator` 的新清理授权检查必须在计划执行和任何副作用前运行；恢复不受该检查影响。App 的扫描、卸载和公共清理入口共用同一授权状态，不只禁用按钮。Helper 的特权写入请求必须携带可校验授权，恢复请求继续保留安全权利；不得将网络请求放入特权 Helper。

独立 `CommercialConfiguration` 资源包含 schemaVersion、productID、apiBaseURL、licensePublicKey；字段必填、拒绝未知字段、HTTPS 和有效 Ed25519 公钥。缺失或无效配置明确阻止付费功能，开发自检用显式测试授权，不引入生产绕过开关。

## 验收与外部条件

本地验收覆盖伪签名、错误金额/商户、通知重放、退款、并发设备限制、离线/回拨、换机、清理拒绝与恢复保留；Swift 与服务端真实跨语言验签。所有验证产物放 Tests/commercial-launch。

真实完成还需要用户配置：付费 Apple 开发者账号、Developer ID 证书私钥、公证 Keychain Profile；支付宝商户和产品权限、RSA2 密钥、真实价格；生产域名和部署权限。未拿到这些之前不声称已经公证或可以收款。正式验收必须有 Apple Accepted 回执、stapler/Gatekeeper 通过，和实际支付宝支付→激活→退款撤销证据。
