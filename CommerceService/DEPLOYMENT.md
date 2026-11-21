# 支付与授权服务运行说明

## 当前可用边界

已实现独立 Node.js HTTP/SQLite 服务、本地 RSA2 验签及 Ed25519 授权、结账页和服务器命令行。定价为一次性人民币 **9.99 元（999 分）**，同时激活 **2 台设备**，离线租约 **7 天（604800 秒）**。买断权益无到期字段；设备租约有明确离线截止时间，到期联网刷新。退款与解绑立即阻止下一次租约签发；已经离线保存的租约最多仍可使用至其 `offlineValidUntil`，不能宣称即时远程抹除离线授权。

用户已确认具备可签约的个体工商户或企业主体，但尚未提供已签约商户、应用权限、生产域名或服务器；配置示例故意含 `null`，会启动失败。当前不能真实收款或声称已经上线。沙箱签名密钥和沙箱买家产生的成功只属于沙箱联调。

## 文件和依赖

- [commerce.mjs](commerce.mjs)：配置校验、原生 SQLite 事务、订单单调状态、设备管理、授权加密和签名。
- [http.mjs](http.mjs)：固定 HTTP 接口、无脚本结账页、JSON 错误边界、大小限制和跨源拒绝。
- [server.mjs](server.mjs)：回环监听及退出处理。
- [admin.mjs](admin.mjs)：服务器本地管理，不开放管理 HTTP 接口。
- [config.example.json](config.example.json)：必须逐项填写的配置，未确定值无默认。
- [deploy/supercleaner-commerce.service](deploy/supercleaner-commerce.service)、[deploy/nginx.conf.example](deploy/nginx.conf.example)：Linux 服务与 HTTPS 代理模板。
- [后端回归](../Tests/commercial-launch/commerce.test.mjs)：真实临时密钥与 SQLite，不连接支付宝或执行真实收款。

最低 Node.js **24.13**；使用内置 `node:http`、`node:sqlite`、`node:crypto` 和 Node 自带 fetch。无 npm 包、无 Python 包、无动态安装，不需要创建 requirements.txt。部署者静态安装受支持的 Node 版本；运行时不会安装依赖。SQLite 使用本机持久磁盘，不放网络文件系统，不通过多台服务器共享数据库文件。

## 配置

将示例复制至仓库之外的 `/etc/supercleaner-commerce/config.json`。所有列出的字段必填；未知字段、HTTP 公网源、错误密钥、组或其他用户可读的私钥文件立即报错。

| 字段 | 必须提供的含义 |
| --- | --- |
| schemaVersion | 固定 `1` |
| host、port | 回环地址（`127.0.0.1` 或 `::1`）和明确端口；模板代理使用 IPv4 |
| publicBaseURL | 自有有效 HTTPS 源，无尾斜杠、路径、查询或凭据 |
| productID、productName | 与 App 完全相同的产品 ID；支付宝商品标题禁止 `/`、`=`、`&` 及控制字符 |
| priceCents、deviceLimit | 当前确定 `999`、`2`；订单持久化创建时的价格 |
| offlineLeaseSeconds | 已确认 `604800`（7天），最长允许366天；关系到离线退款撤销延迟 |
| orderTTLSeconds | 结账有效秒数，支付宝限制为 60–1296000 秒；最后不足一分钟不再发起新支付 |
| requestBodyLimitBytes | 示例显式16384字节，硬性最多1MiB；超出立即413并关闭连接；反向代理限制应一致 |
| rateLimitWindowSeconds、requestRateLimitMax、orderRateLimitMax | 示例显式60秒窗口、最多300个请求、其中最多20个创建订单请求；超过返回429及Retry-After |
| requestTimeoutMilliseconds | HTTP 请求和 SQLite 锁等待上限 |
| upstreamTimeoutMilliseconds | 管理核对时调用支付宝 HTTPS 的超时 |
| alipayGateway | 生产 `https://openapi.alipay.com/gateway.do`；沙箱 `https://openapi-sandbox.dl.alipaydev.com/gateway.do`，不得混用密钥 |
| alipayAppID、alipaySellerID | 真实应用 ID 和收款商户 PID，不能用个人支付宝登录名或收款码代替 |
| alipayPrivateKeyPath | 支付宝开放平台已登记公钥对应的 RSA 应用私钥文件，至少 2048 bit |
| alipayPublicKeyPath | 同一应用/环境的支付宝 RSA 公钥（不是应用公钥）；当前只支持普通公钥模式 |
| licensePrivateKeyPath | 专用 Ed25519 授权私钥文件 |
| licenseEncryptionKeyPath | 恰好 32 字节原始随机 AES 密钥文件，用于静态加密激活码 |
| proxySharedSecretPath | 独立32字节原始随机密钥文件，认证本机反向代理；禁止与其他密钥复用 |
| databasePath | 本机持久磁盘 SQLite 文件绝对路径；目录由服务用户独占可写 |

技术参数推荐值均已显式写入示例，不是代码的缺省值；产品ID固定 `supercleaner.buyout`。真实域名、商户ID和密钥路径仍为null，缺失即启动失败。服务只信任回环来源且持有256bit代理共享密钥的请求；同时要求唯一有效X-Real-IP。Nginx覆盖X-Real-IP和代理认证头，因此外部用户不能通过伪造这些头或X-Forwarded-For改变限流身份。代理按真实公网IP限流，服务也按已认证的真实IP分别计数；不得启用信任任意公网XFF的Nginx real_ip配置。支付通知使用独立计数桶，订单流量不能耗尽通知保留额度；限流使用单调时钟，计数桶最多65536个并及时清理过期项，避免长期累积IP导致内存增长；进程重启会清空内存计数，持续防护仍需代理限流。

配置中的所有文件路径都必须为绝对路径。应用 RSA 私钥、授权 Ed25519 私钥、AES 密钥和代理共享密钥权限为 0600 或 0400，不得进仓库、网站或 App。公钥可以公开，`client-config` 输出可直接用于 App 的独立商业配置。应在受保护的独立备份中同时保存授权签名私钥、AES 密钥和配置；丢失 AES 密钥将无法再次向原购买凭证返回激活码。

生成专用授权密钥的显式操作（生产服务不会自动生成）：

```sh
umask 077
openssl genpkey -algorithm ED25519 -out /etc/supercleaner-commerce/license-private.pem
openssl rand -out /etc/supercleaner-commerce/license-encryption.key 32
openssl rand -out /etc/supercleaner-commerce/proxy-shared.key 32
```

支付宝应用 RSA 密钥须按开放平台流程生成并上传对应公钥。`alipayPublicKeyPath` 必须由平台给出，不能自行生成一把公钥冒充支付宝。

## 启动与管理

在项目根目录运行；命令不会向外部发送邮件或消息。

```sh
node CommerceService/admin.mjs check-config /etc/supercleaner-commerce/config.json
node CommerceService/admin.mjs client-config /etc/supercleaner-commerce/config.json
node CommerceService/admin.mjs proxy-config /etc/supercleaner-commerce/config.json /etc/nginx/supercleaner-proxy-secret.conf
node CommerceService/server.mjs /etc/supercleaner-commerce/config.json
```

`check-config` 只验证配置和密钥，不证明产品签约或真实收款。`proxy-config` 只写入尚不存在的0600私有Nginx include文件，不在终端输出代理密钥；Nginx模板必须引用它。App和支付宝均不需要知道代理共享密钥，由Nginx内部覆盖请求头。直接绕过代理访问回环HTTP也必须通过代理认证，不能把服务端口直接公开。生产用独立低权限服务用户运行，将 SQLite 路径放 `/var/lib/supercleaner-commerce/`。替换服务模板路径、HTTPS 域名/证书并核对显式推荐的端口、请求限制和超时后，部署者执行系统服务安装及 `nginx -t`；未提供服务器权限之前不代称已部署。服务必须只绑定回环，外部仅经 TLS 代理访问。代理不得缓存，不可记录查询串、请求/响应体、激活码或 pollToken；示例已关闭 access log，部署者还须对错误日志、APM、WAF、CDN 和上游监控执行查询参数脱敏，避免代理失败时把 checkout token 写入日志。所有管理与备份文件仅服务用户可读。

服务器本地命令（`订单UUID` 是 App 返回的标准 UUID）：

```sh
node CommerceService/admin.mjs inspect /etc/supercleaner-commerce/config.json 订单UUID
node CommerceService/admin.mjs reconcile /etc/supercleaner-commerce/config.json 订单UUID
node CommerceService/admin.mjs refund-query /etc/supercleaner-commerce/config.json 订单UUID 原退款请求号
node CommerceService/admin.mjs revoke /etc/supercleaner-commerce/config.json 订单UUID '已通过支付宝商家账单核对退款'
node CommerceService/admin.mjs backup /etc/supercleaner-commerce/config.json /安全备份目录/新的备份文件.sqlite
```

核对命令向支付宝发送 RSA2 请求，对**原始响应 JSON 字节**验签，并核对订单、已记录交易号与金额。`reconcile` 不代替完整商户异步通知开通权益；它可在已记录交易关闭时撤销授权。交易查询不保证返回 `seller_id`，因此缺通知的已付款订单返回需要人工核查，不能伪造成功通知。`refund-query` 只有 `refund_status=REFUND_SUCCESS` 且原退款请求号、订单号、交易号和退款金额均匹配时撤销；只有 `10000` 不算退款成功。退款结果不明确时保持待核对，不自动重新申请退款。对账应定期核对商家账单，尤其是部分退款，因为交易状态仍可能为支付成功。

`revoke` **只撤销本地授权，不执行资金退款**。先通过商家平台完成真实退款并核对账单，再撤销；原因不能包含激活码或个人凭据。没有网络管理接口，也没有付款后未经验证的前端开通路径。撤销、已关闭订单、退款均为单调终态；重放旧成功通知不能恢复。`backup` 使用 SQLite `VACUUM INTO` 得到在线一致性快照，目标文件必须尚不存在；恢复时先停止服务，再恢复数据库与对应密钥，最后核对退款/解绑日志，避免恢复旧备份意外复活已经撤销的权益。

## HTTP 协议与保密

所有业务 API 均为 POST JSON、camelCase；生产 HTTPS。精确协议见 [商业设计](../doc/commercial-launch-design.md)。金额只来自服务器配置。订单 ID 与设备 ID 为标准 UUID；为符合支付宝商户单号字符限制，服务内部将 `orderID` 去连字符后作为 `out_trade_no`，并严格反向映射，不改变客户端 UUID 协议。

- `/v1/orders`：`{email,deviceID}` → `{orderID,pollToken,checkoutURL}`。
- `/v1/orders/status`：`{orderID,pollToken}` → `{status,licenseKey}`。pending/revoked/closed 时 licenseKey 为 null；随机 token 为 256 bit，数据库只存哈希。未知订单与错误 token 返回同一错误。
- `/checkout/<orderID>?token=<pollToken>`：GET 安全结账，无脚本、无第三方资源、no-store/no-referrer/CSP；表单不携带 pollToken。页面只跳转支付宝，不判断支付成功。
- `/v1/alipay/notify`：POST form-urlencoded，拒绝重复字段，验证 RSA2、UTF-8、app_id、seller_id、订单、整数分金额、交易号全局唯一及交易状态；refund_fee 为正或存在有效 gmt_refund 均撤销，不能借旧 trade_status 开通。
- `/v1/licenses/activate`、`/refresh`：`{email,licenseKey,deviceID,deviceName}` → `{claimsData,signature}`；刷新仅允许仍处于激活状态的同设备，解绑后须明确激活，不能自动恢复。
- `/v1/licenses/devices`：`{email,licenseKey}` → `{devices:[{deviceID,deviceName,activatedAt}]}`。
- `/v1/licenses/deactivate`：`{email,licenseKey,deviceID}` → `{deactivated:true}`；重复幂等。

授权 claims 为 `{licenseID,productID,email,deviceID,issuedAt,offlineValidUntil,capabilities}`；时间 Unix 秒整数，capabilities 精确为 standardScan/agentScan/newCleanup。对 claimsData 解码后的原始 UTF-8 字节验 Ed25519，不重新序列化。公钥须通过可信 App 配置固定；本服务不会把私钥提供给客户端。除购买订单的原 pollToken 外，不通过无 token 查询或返回跳转发放激活码。HTTP 端不允许跨源读取，也不提供宽松 CORS。服务不记录请求 URL、请求体、激活码或 pollToken。HTTP只接受单斜杠开头的origin-form路径，拒绝//、反斜线、控制符及片段，防止恶意request-target触发URL构造异常。可预期输入错误显式返回 `{error}`；配置、数据库或签名等不可预期异常立即抛出，交由服务管理器报告和重启，不吞掉故障。

## 自检与跨语言验证

```sh
node --test Tests/commercial-launch/commerce.test.mjs
SUPERCLEANER_EXPORT_INTEROP_FIXTURE=1 node --test --test-name-pattern='输出跨语言' Tests/commercial-launch/commerce.test.mjs
```

第一条执行真实 HTTP 并发、RSA2/Ed25519、金额/商户伪造、通知幂等/乱序退款、持久解绑、命令行撤销和在线备份。沙盒禁止回环监听时需要在允许本机临时监听的环境运行，不能跳过 HTTP 验收后声称全通过。第二条导出 [公开跨语言夹具](../Tests/commercial-launch/fixtures/license.json)，包含真实服务签发的 SignedLicense、公钥、productID 和 deviceID，不包含私钥。普通测试不改写该夹具；它用于协议验证，绝不是生产授权。临时 SQLite、密钥和中间输出在 `Tests/temporary/`，成功测试自动删除临时密钥目录；失败遗留目录也不得发布。失败到通过证据由执行会话保存于该目录，不把机器日志当源码分发。

正式上线仍必须完成真实支付→异步通知→激活→解绑/换机→退款→刷新拒绝的证据，并核对 TLS、代理日志脱敏和受保护备份恢复。当前自动化验证不连接支付宝，不能替代官方沙箱或生产支付验收。

## 个人支付宝与官方依据

只有个人支付宝账号不足以证明能调用电脑网站支付。支付宝官方帮助说明，个人或企业账号可申请接口，但仍必须满足具体产品准入。官方支付接入文章说明，没有营业执照的自然人通常不能开通标准网站/App 商家支付接口；更稳妥的路径是依法登记个体工商户，以对应主体完成认证并按产品要求审核。个体工商户也不是自动通过：仍需真实网站、商品与价格、联系方式、退款/隐私规则，以及后台要求的域名、备案和行业资料。账号实名、营业执照/经营者核验、签约协议、网站资质和支付产品审核需账号所有者人工完成；本项目不能替用户伪造身份资料或把个人收款码/监听通知改造成支付 API。

以下均为官方来源（核对日期 2026-11-21；实际签约以控制台显示和审核结果为准）：

- [支付宝商家帮助：签约需要什么条件](https://help.alipay.com/support/help_detail.htm?help_id=396843)：基础实名与网站条件不代替产品准入。
- [支付宝官方：个人开发者如何开通支付宝支付功能](https://aipay.alipay.com/article/3759)：自然人、营业执照、个人码与商家 API 的区别。
- [支付宝官方：个体工商户申请各支付产品](https://aipay.alipay.com/article/3907)：产品分别签约、真实经营场景与审核资料。
- [支付宝商家产品入口](https://b.alipay.com/page/product-mall/all-product?productId=I1011000290000001000)：申请时核实电脑网站支付准入；页面需要交互/登录，不能据公开空页面断言已具权限。
- [支付宝 page.pay 参数](https://aipay.alipay.com/docs/vibe-pay/ai-web-app-payment-qianyi/api-list/alipay-trade-page-pay.html)：FAST_INSTANT_TRADE_PAY、金额、商户单号及 time_expire。
- [支付宝官方 SDK 签名实现](https://github.com/alipay/alipay-sdk-nodejs/blob/master/src/util.ts) 与 [通知/响应验签](https://github.com/alipay/alipay-sdk-nodejs/blob/master/src/alipay.ts)：RSA2 为 SHA256、通知去 sign/sign_type、只解码一次、响应取原始对象字节。
- [支付宝官方 Java 交易查询响应结构](https://github.com/alipay/alipay-sdk-java-all/blob/master/v2/src/main/java/com/alipay/api/response/AlipayTradeQueryResponse.java)：交易状态和查询字段范围。
- [支付宝退款查询接口](https://aipay.alipay.com/docs/vibe-pay/ai-web-app-payment-qianyi/api-list/alipay-trade-fastpay-refund-query.html)：10000 不等于退款成功，须检查 REFUND_SUCCESS 并使用原退款请求号。

- [Node.js 24.13 SQLite官方文档源码](https://github.com/nodejs/node/blob/v24.13.0/doc/api/sqlite.md)：验证DatabaseSync、prepare/run/get/all/exec及测试使用的isOpen均受目标版本支持。
