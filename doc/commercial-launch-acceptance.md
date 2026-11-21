# 商业上线验收状态

核验日期：2026-11-21。目标仍在进行中；本地源码、构建和模拟边界通过，不代表已经取得 Apple 发行身份、完成公证或开通真实收款。

## 已验证

| 要求 | 直接证据 | 结论 |
| --- | --- | --- |
| 一次买断、9.99元、两台、7天离线，无订阅/续费 | [生产样例](../CommerceService/config.example.json)、[客户端商业区](../Sources/CleanerApp/CommercialSettingsView.swift) | 已实现；未知商户与域名仍为null |
| 金额/商户/订单/交易号验签，退款不被旧通知复活 | [后端行为测试](../Tests/commercial-launch/commerce.test.mjs)、node-tests-final.log | 真实RSA、SQLite、HTTP夹具通过；未调用真实支付宝 |
| 并发两台限制，解绑和换机，旧离线租约边界 | 同上及client-root-final.log | 本地行为通过；实体多Mac仍待生产验收 |
| Keychain实现、HTTPS同源、拒绝跳转、响应上限 | [客户端](../Sources/CleanerApp/CommercialAccess.swift)、[运行套件](../Tests/commercial-launch/client-runtime.swift) | 真实URLSession与测试存储通过；未写用户真实钥匙串 |
| 过期自动续期、断网保留、403撤销、旧响应竞态、停止轮询、观察时间持久化 | client-root-final.log | 全部通过，包含重建actor后的持久化回拨验证 |
| Node原始签名可被Swift CryptoKit验真 | interop-root.log、[跨语言检查](../Sources/CoreContractChecks/CommercialInteropContract.swift) | 已通过，不重新序列化签名原文 |
| App未授权扫描/新清理拒绝，安全权利保留 | app-commercial-root.log、release-commercial-root.log | Debug与Release实际AppModel自检均通过 |
| Helper独立拒绝无商业凭据/伪造凭据，恢复保留 | helper-green.log、[集成契约](../Sources/CoreContractChecks/HelperIntegrationContract.swift) | 真实文件夹具通过，不注册系统daemon |
| 新清理在计划刷新和写入前拒绝，恢复/维护不收费 | planning-root.log、[执行契约](../Sources/CoreContractChecks/PlanningExecutionContract.swift) | 已通过 |
| 原有与新增Swift回归 | swift-tests-full.log | **352项，0失败**；沙盒外运行，包含真实Trash夹具 |
| 后端、公证恢复、签名原子提交、规则发布 | node-tests-final.log | **58项，0失败、0跳过**；含28项真实Swift规则回读 |
| Release优化App与Helper源码编译 | release-app-build-approved.log、helper-app-build.log | 编译成功；不是Apple正式签名包 |
| 公证恢复不重复上传，内容变化/不确定上传拒绝 | [公证测试](../Tests/commercial-launch/notarization.test.mjs) | 模拟Apple CLI通过，未提交真实Apple任务 |
| DMG签名/时间戳失败后可恢复 | [签名测试](../Tests/commercial-launch/release-signing.test.mjs) | 模拟签名中断先失败后通过；不代表真实DMG装订通过 |
| 规则签名生成端，三把密钥独立与内置基线 | [工具](../Scripts/sign-rule-update.mjs)、[Swift回读](../Sources/CoreContractChecks/RulePublishingContract.swift) | 原字节、schema、坏签名/时间/假verifier及三种密钥复用均验证 |
| 中英文、源码覆盖与占位符一致 | Scripts/check-localizations.py | **1340条双语消息通过** |
| 逐文件必要性与最终差异 | [修改复核](commercial-launch-change-review.md)、git diff --check | 无空白错误；按用户追加指令提交至远程feat/marketing，包含既有旧DMG删除；生产上线仍未完成 |

最终验收日志已纳入本批提交，均位于 `Tests/commercial-launch/`，不是应用公开发布目录。测试私钥、数据库、编译缓存仍放受忽略的fixtures或构建目录；临时测试二进制由runner清理。部分子任务早期红/绿日志位于 `Tests/temporary/`，不作为交付产物。

## 尚未完成的外部验收

| 明确要求 | 当前证据 | 继续所需 |
| --- | --- | --- |
| 有效Developer ID Application身份 | 经批准只读检查仅发现两个本地开发签名；用户未加入会员 | 本人完成Apple会员与身份核验，申请证书并导入对应私钥 |
| Apple公证Accepted | 没有真实submission ID或Accepted回执 | 有效Developer ID及本机公证Keychain Profile |
| App/DMG真实staple和Gatekeeper | 尚无本期正式发布包 | 真实公证完成后执行发布脚本及干净Mac安装 |
| 支付宝生产签约与密钥 | 用户有可签约经营主体，但目前仅个人支付宝账号；样例配置拒绝启动 | 商户认证、网页应用、电脑网站支付权限、APP_ID/PID及服务器密钥 |
| 生产HTTPS授权服务与销售站点 | 未提供主机、域名或托管权限，没有部署URL | 确定托管平台/费用范围，完成域名、TLS、部署与备份 |
| 9.99元实际付款→两台激活→退款撤销 | 没有真实交易记录 | 生产配置和本人明确的测试交易/退款确认 |
| 正式签名后的真实Keychain体验与最低系统安装 | 运行套件使用测试存储，未动用户授权数据 | 签名包和测试Mac，验证新装、升级、钥匙串提示与恢复 |

生产门禁已重新运行：`publish-release.sh --preflight` 明确拒绝缺少正式配置/Developer ID/公证账户，服务配置检查明确拒绝缺少 `publicBaseURL`。这是预期的未配置状态，不能改成默认放行来宣称完成。

## 重现关键验证

```bash
SUPERCLEANER_RULE_VERIFIER="$PWD/.build/commercial-app/out/Products/Debug/CoreContractChecks" \
  node --test Tests/commercial-launch/*.test.mjs

Tests/commercial-launch/check-client.sh \
  "$PWD/.build/commercial-app/out/Products/Debug" \
  "$PWD/.build/commercial-app/module-cache"

SUPERCLEANER_EXPORT_INTEROP_FIXTURE=1 \
  node --test --test-name-pattern='输出跨语言' Tests/commercial-launch/commerce.test.mjs
.build/commercial-app/out/Products/Debug/CoreContractChecks \
  --check-license-interop "$PWD/Tests/commercial-launch/fixtures/license.json"
```

这些路径对应本次实际构建；更换SwiftPM版本或scratch后应以 `swift build --show-bin-path` 的实际输出为准。Node HTTP测试在测试沙盒禁止本地监听时需经批准运行；不得删除断言或将不能执行写成通过。
