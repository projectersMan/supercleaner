# 商业上线所需账号与生产配置

本期规则：人民币 **9.99 元一次买断、两台 Mac、7 天离线凭据**，无订阅和自动续费。到期联网刷新的是设备凭据，不是重新购买。项目仍按 GPL v3 发布，收费范围是官方分发及配套授权服务。

## 当前仍需本人办理的事项

| 事项 | 本人需要完成 | 办理后交给开发流程的信息 |
| --- | --- | --- |
| Apple 开发者会员 | 使用本人/组织账号完成身份核验、协议及 Apple 会员付款 | 审核通过；公开的 Team ID |
| Developer ID Application | 在有权限的 Apple 开发者账号中申请证书，保留对应私钥并导入登录钥匙串 | `security find-identity -v -p codesigning` 中该身份的 SHA-1；无需发送私钥 |
| Apple 公证凭据 | 在本机交互配置 notarytool 的 Keychain Profile | 仅 Profile 名称 |
| 支付宝商户 | 用已有经营主体完成商家认证、创建开放平台网页应用并申请电脑网站支付权限 | app_id、seller_id、审核状态；密钥只放服务器 |
| 生产托管 | 提供可管理的 Linux 主机与生产 HTTPS 域名，或指定希望使用的托管平台 | 主机管理方式、域名/DNS权限及明确的费用范围 |

这些步骤涉及身份核验、商户审核或第三方付费，不能用本地模拟结果代替。请不要在聊天中发送密码、私钥、支付宝登录验证码或公证密码。取得账号权限后，证书核验、配置、构建、部署和测试由开发流程继续完成。

Apple 会员是软件发行方自己的服务费用，与售给用户的买断授权无关；由本人确认条款与付款。官方入口：[注册 Apple 开发者计划](https://developer.apple.com/programs/enroll/)、[Developer ID 证书说明](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)、[公证工作流](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)。

公证凭据请直接使用 Apple 原生交互命令存入钥匙串，不将密码写入脚本：

```bash
xcrun notarytool store-credentials "SuperCleaner-notary"
```

支付宝从[开放平台](https://open.alipay.com/)办理；电脑网站支付接口为 `alipay.trade.page.pay`。已有营业主体不等于已签约支付产品，最终准入、应用和域名要求以商户控制台审核为准。个人收款码无法替代签名通知、交易核对和退款流程。

## 生产服务配置

服务源码、配置样例及部署文件见 [CommerceService](../CommerceService)。服务器保存支付宝 RSA2 私钥、支付宝平台公钥、Ed25519 授权私钥、授权码加密密钥和 SQLite 数据库；这些均不得进入客户端、仓库或公开下载目录。

公开客户端配置由服务管理工具导出，只包含产品 ID、HTTPS 地址、验签公钥：

```bash
node CommerceService/admin.mjs client-config /etc/supercleaner-commerce/config.json
```

将输出保存为本机私密配置目录中的 `commercial-configuration.json`，再通过 `SUPERCLEANER_COMMERCIAL_CONFIG` 指定绝对路径。现有 [公开配置样例](../Resources/commercial-configuration.example.json) 故意保留尚未取得的域名和公钥为空，不能直接发布。

## 构建与公证

生产发布还需要 [更新配置](../Resources/release-configuration.example.json)、固定 Developer ID 和 Sparkle 发布签名账户。参数均必须明确提供：

```bash
export SUPERCLEANER_RELEASE_CONFIG='/本机私密配置目录/release-configuration.json'
export SUPERCLEANER_COMMERCIAL_CONFIG='/本机私密配置目录/commercial-configuration.json'
export SUPERCLEANER_SIGN_IDENTITY='实际 Developer ID Application 身份 SHA-1'
export SUPERCLEANER_NOTARY_PROFILE='实际 Keychain Profile 名称'
export SUPERCLEANER_SPARKLE_ACCOUNT='实际 Sparkle 签名钥匙串账户'
export SUPERCLEANER_PREVIOUS_BUILD_NUMBER='上一正式发布构建号，首次发布填写0'
./Scripts/build-app.sh
./Scripts/publish-release.sh --preflight
./Scripts/publish-release.sh --publish
```

正式构建会递增版本；公证恢复过程不重新构建、不递增版本。中断后保持原构建、配置和 staging 不变，使用：

```bash
./Scripts/publish-release.sh --resume
```

流程先公证并装订 App，再创建、公证并装订包含该 App 的 DMG。不可变提交包和 Apple submission ID 留在 `build/releases/<版本>-<构建>/`；仅最终 `public/` 可用于发布。`LOCAL-GATES-PASSED` 只是本地签名、公证和包检查通过，不能替代干净 Mac 安装及实际支付验收。

## 实际销售验收

必须保留 Apple 的 Accepted 回执和 App/DMG 票据验证，完成一笔真实支付宝付款（金额 9.99 元）到 App 激活、第二台激活、第三台拒绝、解绑换机、断网使用、7 天凭据刷新以及退款后撤销。退款相关测试使用明确的测试订单，不影响真实客户订单；执行真实扣款/退款时需本人确认。

当前资料不齐时，生产发布与真实收款保持未完成；不能把模拟支付宝签名测试或模拟 Apple CLI 测试写成“已开通收款”“已经公证”。
