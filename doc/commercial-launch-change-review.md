# 商业上线逐文件修改复核

本次仅修改买断授权、支付、发布及其必要回归与现行文档；现按用户明确指令将全部本地改动提交并推送到远程 feat/marketing，本地继续使用 codex/alipay-buyout。每个文件的改动目的如下，均保留为正向且必要的修改。

| 文件 | 必要性与复核结论 |
| --- | --- |
| [Tests/commercial-launch/swift-tests-full.log](../Tests/commercial-launch/swift-tests-full.log) | 保存完整Swift回归的可审阅输出，提交前重新运行。 |
| [Tests/commercial-launch/node-tests-final.log](../Tests/commercial-launch/node-tests-final.log) | 保存支付、HTTP、规则签名和公证恢复58项最终结果，提交前重新运行。 |
| [Tests/commercial-launch/client-root-final.log](../Tests/commercial-launch/client-root-final.log) | 保存根agent客户端语义、取消和时间回拨验收记录。 |
| [Tests/commercial-launch/interop-root.log](../Tests/commercial-launch/interop-root.log) | 保存Node签发凭证被Swift原字节验真的结果。 |
| [Tests/commercial-launch/app-commercial-root.log](../Tests/commercial-launch/app-commercial-root.log) | 保存Debug App实际商业门禁与恢复权利自检结果。 |
| [Tests/commercial-launch/release-commercial-root.log](../Tests/commercial-launch/release-commercial-root.log) | 保存Release App实际商业门禁自检结果。 |
| [Tests/commercial-launch/helper-green.log](../Tests/commercial-launch/helper-green.log) | 保存Helper独立商业验签与恢复契约通过结果。 |
| [Tests/commercial-launch/planning-root.log](../Tests/commercial-launch/planning-root.log) | 保存新清理零副作用拒绝及恢复保留的执行契约结果。 |
| [Tests/commercial-launch/release-app-build-approved.log](../Tests/commercial-launch/release-app-build-approved.log) | 保存Release优化构建成功结果，不冒充Apple签名或公证。 |
| [Tests/commercial-launch/helper-app-build.log](../Tests/commercial-launch/helper-app-build.log) | 保存Helper编译成功记录。 |
| [Tests/commercial-launch/final-production-preflight.log](../Tests/commercial-launch/final-production-preflight.log) | 保存缺正式发行资料时正确拒绝的结果，说明真实公证尚未完成。 |
| [Tests/commercial-launch/final-merchant-preflight.log](../Tests/commercial-launch/final-merchant-preflight.log) | 保存缺生产域名等配置时明确失败的结果，说明真实收款尚未开通。 |
| [doc/commercial-launch-acceptance.md](commercial-launch-acceptance.md) | 逐条对照完整目标记录直接证据，明确真实签名、公证、托管与收款尚未完成，避免把本地通过当作已能销售。 |
| [docs/architecture.md](../docs/architecture.md) | 为原完整架构文档加入现行商业流程入口，避免与doc现行补充脱节。 |
| [docs/development.md](../docs/development.md) | 为原完整开发指南加入商业验证与规则签名入口，保持两处在用开发文档一致。 |
| [CommerceService/DEPLOYMENT.md](../CommerceService/DEPLOYMENT.md) | 准确记录部署、密钥隔离、签约、代理、备份和真实验收要求。 |
| [CommerceService/admin.mjs](../CommerceService/admin.mjs) | 服务器本地配置、公钥、私有代理配置、交易/退款核对、撤销及备份管理，不开放管理HTTP接口。 |
| [CommerceService/commerce.mjs](../CommerceService/commerce.mjs) | 整数金额、严格配置、支付验签、持久事务、退款单调撤销、两设备上限、加密激活码及有限租约。 |
| [CommerceService/config.example.json](../CommerceService/config.example.json) | 显式写入999分、两台、7天和技术参数；未知真实商户/域名/密钥不填伪值。 |
| [CommerceService/deploy/nginx.conf.example](../CommerceService/deploy/nginx.conf.example) | TLS入口、可信代理头覆盖和独立来源限流；不公开共享代理密钥，不记录结账token。 |
| [CommerceService/deploy/supercleaner-commerce.service](../CommerceService/deploy/supercleaner-commerce.service) | 独立低权限系统服务和受限持久写入目录，明确崩溃重启。 |
| [CommerceService/http.mjs](../CommerceService/http.mjs) | 固定接口、安全结账、恶意输入拒绝、限流、受限请求体和可信代理身份，敏感响应禁止缓存。 |
| [CommerceService/server.mjs](../CommerceService/server.mjs) | 显式检查Node运行时，回环监听和服务生命周期管理，无动态依赖安装。 |
| [README.md](../README.md) | 新增买断使用入口、永久权益与7天凭据说明；说明尚未正式销售，移除已不存在的旧DMG下载链接。 |
| [Resources/commercial-configuration.example.json](../Resources/commercial-configuration.example.json) | 提供纯公开产品/地址/验签配置结构，空未知字段确保不能误当生产配置。 |
| [Scripts/build-app.sh](../Scripts/build-app.sh) | 验证并打包独立商业公开配置，私钥不进入应用；保留现有构建版本分配。 |
| [Scripts/check-production-signing.sh](../Scripts/check-production-signing.sh) | 正式销售门禁强制商业配置有效，避免签名正确却无法验证付费。 |
| [Scripts/notarize-artifact.sh](../Scripts/notarize-artifact.sh) | 保存不可变文件哈希与Apple submission ID，重复执行不重复提交，上传不确定时要求核对。 |
| [Scripts/publish-release.sh](../Scripts/publish-release.sh) | App和DMG分别公证/装订；按相同构建恢复，pending签名验证后原子提交，动态定位构建产物。 |
| [Scripts/sign-release-artifact.sh](../Scripts/sign-release-artifact.sh) | 签名或时间戳失败不产生已提交DMG；成功验证后才原子改名，支持中断恢复。 |
| [Scripts/sign-rule-update.mjs](../Scripts/sign-rule-update.mjs) | 补齐正式发布原有缺失的规则签名生成端；独立密钥、原字节签名、真实Swift回读、拒绝覆盖和链接。 |
| [Sources/CleanerApp/AppInfrastructure.swift](../Sources/CleanerApp/AppInfrastructure.swift) | 创建共享CommercialAccess并注入协调器和Helper，统一生产授权来源。 |
| [Sources/CleanerApp/AppModel.swift](../Sources/CleanerApp/AppModel.swift) | 扫描/深扫/Agent/清理接共享门禁，授权失败明确显示；启动和现有维护循环续期，旧自检显式注入签名夹具。 |
| [Sources/CleanerApp/CleanerApp.swift](../Sources/CleanerApp/CleanerApp.swift) | 加入可重复运行的实际AppModel商业授权自检，完成后退出，不提供GUI免授权入口。 |
| [Sources/CleanerApp/CleanerSmokeTest.swift](../Sources/CleanerApp/CleanerSmokeTest.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Sources/CleanerApp/CommercialAccess.swift](../Sources/CleanerApp/CommercialAccess.swift) | Keychain持久化、同源HTTPS、签名和设备绑定、自动续期、撤销、异步竞态与持久时间回拨防护。 |
| [Sources/CleanerApp/CommercialLicenseFixture.swift](../Sources/CleanerApp/CommercialLicenseFixture.swift) | 自检使用真Ed25519、内存存储和显式注入，保留既有清理回归且不写用户钥匙串。 |
| [Sources/CleanerApp/CommercialSettingsView.swift](../Sources/CleanerApp/CommercialSettingsView.swift) | 原生购买、可取消付款检查、激活/复制激活码、刷新和解绑；错误可见，区分买断与凭据期限。 |
| [Sources/CleanerApp/HelperSettingsModel.swift](../Sources/CleanerApp/HelperSettingsModel.swift) | 向特权新清理请求提供经过共享授权验证的设备签名凭证。 |
| [Sources/CleanerApp/PermissionsView.swift](../Sources/CleanerApp/PermissionsView.swift) | 在既有设置Form中加入买断购买、激活和设备管理区。 |
| [Sources/CleanerCore/CleanupExecutionCoordinator.swift](../Sources/CleanerCore/CleanupExecutionCoordinator.swift) | 必需授权依赖在任何新清理副作用之前执行，恢复及既有内容维护不受影响。 |
| [Sources/CleanerCore/CommercialAuthorization.swift](../Sources/CleanerCore/CommercialAuthorization.swift) | 定义独立XPC设备授权证明，不包含私钥或支付凭据。 |
| [Sources/CleanerCore/CommercialConfiguration.swift](../Sources/CleanerCore/CommercialConfiguration.swift) | 四字段必填公开配置，拒绝未知字段、占位域、非HTTPS和无效公钥；缺失明确失败。 |
| [Sources/CleanerCore/HelperClient.swift](../Sources/CleanerCore/HelperClient.swift) | 协议升级4并随特权新清理传签名证明，防止误用旧Helper。 |
| [Sources/CleanerCore/HelperFileOperations.swift](../Sources/CleanerCore/HelperFileOperations.swift) | 服务端独立验证商业凭据，再执行受限文件操作；缺许可仍允许恢复。 |
| [Sources/CleanerCore/HelperProtocol.swift](../Sources/CleanerCore/HelperProtocol.swift) | 定义商业证明和明确拒绝原因，区分收费新清理与免付费恢复操作。 |
| [Sources/CleanerCore/LicenseStore.swift](../Sources/CleanerCore/LicenseStore.swift) | 去除trial与无绑定永久token；原始字节验签后校验产品/设备/期限/时间，安全权利不收费。 |
| [Sources/CleanerCore/Resources/en.lproj/Localizable.strings](../Sources/CleanerCore/Resources/en.lproj/Localizable.strings) | 补齐买断、错误、续期与设备管理的中英对应文案，并通过占位符/源码覆盖检查。 |
| [Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings](../Sources/CleanerCore/Resources/zh-Hans.lproj/Localizable.strings) | 补齐买断、错误、续期与设备管理的中英对应文案，并通过占位符/源码覆盖检查。 |
| [Sources/CleanerHelper/HelperService.swift](../Sources/CleanerHelper/HelperService.swift) | ping升级4，与新的必需商业授权语义保持一致。 |
| [Sources/CleanerHelper/main.swift](../Sources/CleanerHelper/main.swift) | 启动时加载签名资源中的商业公开配置，错误明确输出，避免使用错误产品或公钥。 |
| [Sources/CoreContractChecks/CommercialContract.swift](../Sources/CoreContractChecks/CommercialContract.swift) | 行为验证签名原文、租约、产品/设备、回拨、安全权利和严格配置。 |
| [Sources/CoreContractChecks/CommercialInteropContract.swift](../Sources/CoreContractChecks/CommercialInteropContract.swift) | 直接验证Node服务签发的原始凭据可被Swift CryptoKit接受。 |
| [Sources/CoreContractChecks/HelperExecutionContract.swift](../Sources/CoreContractChecks/HelperExecutionContract.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Sources/CoreContractChecks/HelperIntegrationContract.swift](../Sources/CoreContractChecks/HelperIntegrationContract.swift) | 真实文件夹具验证管理员权限不足以绕过商业凭据、伪签名拒绝及无商业许可恢复。 |
| [Sources/CoreContractChecks/PlanningExecutionContract.swift](../Sources/CoreContractChecks/PlanningExecutionContract.swift) | 验证未授权在计划刷新和落盘前拒绝，同时验证恢复和维护可执行。 |
| [Sources/CoreContractChecks/ReviewRegressionContract.swift](../Sources/CoreContractChecks/ReviewRegressionContract.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Sources/CoreContractChecks/RulePublishingContract.swift](../Sources/CoreContractChecks/RulePublishingContract.swift) | 使用App相同RuleStore及内置规则基线，验证发布包原始内容、签名、版本和完整schema。 |
| [Sources/CoreContractChecks/main.swift](../Sources/CoreContractChecks/main.swift) | 注册商业配置/跨语言验签/规则发布验证命令，供构建和发布复用。 |
| [Tests/CleanerCoreTests/ApplicationDockServiceTests.swift](../Tests/CleanerCoreTests/ApplicationDockServiceTests.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Tests/CleanerCoreTests/CleanupExecutionCoordinatorTests.swift](../Tests/CleanerCoreTests/CleanupExecutionCoordinatorTests.swift) | 未授权新清理必须零文件/历史/日志副作用，其余用显式隔离测试授权。 |
| [Tests/CleanerCoreTests/CommercialConfigurationTests.swift](../Tests/CleanerCoreTests/CommercialConfigurationTests.swift) | 验证必填字段、未知字段、生产HTTPS、占位域及公钥边界。 |
| [Tests/CleanerCoreTests/DeletionCancellationTests.swift](../Tests/CleanerCoreTests/DeletionCancellationTests.swift) | 显式注入隔离测试授权；真实Trash失败时显示回执便于定位沙盒限制，不降低断言。 |
| [Tests/CleanerCoreTests/LicenseStoreTests.swift](../Tests/CleanerCoreTests/LicenseStoreTests.swift) | 替换旧trial测试，验证新的设备签名与有限离线租约。 |
| [Tests/CleanerCoreTests/MutableCleanupTests.swift](../Tests/CleanerCoreTests/MutableCleanupTests.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Tests/CleanerCoreTests/PackageReceiptCleanupTests.swift](../Tests/CleanerCoreTests/PackageReceiptCleanupTests.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Tests/CleanerCoreTests/UninstallPermissionRecoveryTests.swift](../Tests/CleanerCoreTests/UninstallPermissionRecoveryTests.swift) | 现有协调器构造显式注入隔离测试授权，适配新的必需依赖；原业务断言和安全边界保留。 |
| [Tests/commercial-launch/check-client.sh](../Tests/commercial-launch/check-client.sh) | 重复运行客户端行为测试与本地化检查，测试二进制放fixtures且退出时清理。 |
| [Tests/commercial-launch/client-runtime.swift](../Tests/commercial-launch/client-runtime.swift) | 真实URLSession语义验证购买/激活/续期、取消、设备换机、异步竞态、断网与时钟观察持久化。 |
| [Tests/commercial-launch/commerce.test.mjs](../Tests/commercial-launch/commerce.test.mjs) | 真实RSA/Ed25519、SQLite及HTTP边界测试，覆盖并发设备、退款、异常请求和代理隔离。 |
| [Tests/commercial-launch/core-reserved-domain.json](../Tests/commercial-launch/core-reserved-domain.json) | 保留.test生产占位域的明确拒绝夹具，防止配置误放行。 |
| [Tests/commercial-launch/notarization.test.mjs](../Tests/commercial-launch/notarization.test.mjs) | 模拟Apple CLI验证提交幂等、变更拒绝及上传不确定处理，不冒充真实公证。 |
| [Tests/commercial-launch/release-signing.test.mjs](../Tests/commercial-launch/release-signing.test.mjs) | 模拟签名失败后恢复，验证未完成签名不能形成提交产物。 |
| [Tests/commercial-launch/rule-publishing.test.mjs](../Tests/commercial-launch/rule-publishing.test.mjs) | 真实Swift回读签名包，验证独立密钥、坏数据、假验证器、内置基线及不覆盖输出。 |
| [build/SuperCleaner-0.5.10.dmg](../build/SuperCleaner-0.5.10.dmg) | 用户进入任务前已有的删除；本任务保留该状态，没有恢复或删除其它用户文件。 |
| [doc/architecture.md](../doc/architecture.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-launch-change-review.md](../doc/commercial-launch-change-review.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-launch-design.md](../doc/commercial-launch-design.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-launch-findings.md](../doc/commercial-launch-findings.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-launch-plan.md](../doc/commercial-launch-plan.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-launch-progress.md](../doc/commercial-launch-progress.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/commercial-onboarding.md](../doc/commercial-onboarding.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [doc/development.md](../doc/development.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |
| [docs/production-release-checklist.md](../docs/production-release-checklist.md) | 更新现行架构、开发、协议、操作、证据或逐文件审计，明确未完成外部验收；历史发布记录不改写。 |

## 自我审视与已实施修正

- 初版HTTP边界只处理JSON语法错误，没有覆盖URL解析异常；现对请求目标先验证，并验证恶意请求后进程仍可服务。
- 初版本地直连限流测试未覆盖Nginx代理拓扑；现以可信回环代理、私有共享密钥及覆盖的真实IP分桶，并验证用户间不互相耗尽。
- 保留公证submission ID并不等于发布阶段可恢复；现签名验证后才原子形成不可变提交包，补齐中断测试。
- 初版取消只取消外层任务；现取消真实轮询HTTP任务。初版时间基准只记录成功授权；现记录已验签租约的失败观察时间，并允许可信新租约在时钟校准后恢复。
- 纯本地授权无法保证绝对防破解；本次保持GPL，无权撤回历史GPL授权；没有承诺闭源或绝对防篡改。

## 局部与全局下一步评分

| 建议 | 分数 | 执行状态 |
| --- | --- | --- |
| 局部：封闭HTTP输入异常、修复可信代理来源与内存限流边界 | 99 | 已实施，真实HTTP回归 |
| 局部：真实停止付款检查，避免挂起请求继续轮询 | 89 | 已实施，取消语义回归 |
| 局部：失败观察时间持久化，校准后可从新签名租约恢复 | 90 | 已实施，跨actor持久化回归 |
| 局部：公证前签名产物原子提交并支持原任务恢复 | 94 | 已实施，模拟CLI中断回归 |
| 全局：App、协调器和Helper统一授权，恢复保留 | 98 | 已实施，Swift及实际App自检 |
| 全局：补齐独立规则签名生成端与同源验证器 | 96 | 已实施，28项真实Swift规则回读通过 |
| 全局：完成Apple真实签名、公证与干净Mac安装 | 100 | 等待会员、证书、公证凭据与测试设备；不伪造完成 |
| 全局：部署HTTPS并完成9.99元付款、两台激活、退款撤销 | 100 | 等待商户权限、生产密钥和托管权限后继续 |

所有不低于85分且当前可执行的代码修正均已继续实施；外部账号/付款/审核不能用源码变更代替。没有提出需低分扩展而等待确认的额外功能。
