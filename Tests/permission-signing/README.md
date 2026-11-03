# 权限识别与固定签名验证

用户已明确批准本批权限识别与连续构建签名稳定性定向检查。

```sh
swift test --disable-sandbox --cache-path .build/release-cache --scratch-path .build/release-scratch --configuration release --filter PermissionStatusTests
zsh Tests/permission-signing/verify-signing.sh
```

权限检查覆盖专用保护位置可读而其他App目录拒绝的情况、EPERM明确拒绝、缺失与EIO一般错误，以及原有降级扫描策略；另覆盖用户探测目录不存在、系统同类目录可读的实机回归。签名检查使用代码不同的两个C夹具、同一固定证书与同一标识；验证DR相同、旧DR接受新版，随后验证相同标识的ad-hoc替换仍被拒绝。夹具不运行、不安装，结束后清理；不修改TCC或任何用户访问授权。

证书由用户选择的本机开发身份提供，私钥只存在登录钥匙串。首次代码签名信任、私钥访问确认与当前App的FDA授权均由用户本人处理。

当前结果：PermissionStatusTests 6项通过，无失败；可读专用探测目录时不读取其他App目录，明确拒绝、缺失和EIO状态分类正确。用户保存代码签名信任并确认私钥使用后，签名稳定性脚本通过：不同内容产物的DR相同，旧DR接受新版，同标识的ad-hoc替换被拒绝。macOS对本机自签身份生成certificate leaf指纹形式的DR；检查同时接受该形式和Apple anchor形式，并拒绝cdhash形式。原检查仅接受anchor，首次验证失败后已按实际证书绑定语义修正，未放宽生产门禁。

最终包核对见[package-verification.txt](package-verification.txt)。App已覆盖固定安装路径，版本0.2.37（70）；设置和扫描前窗口均无文件夹授权区，预检结束后未验证FDA仍可开始扫描。本次未执行清理。用户确认首次身份迁移FDA后，发现用户探测目录不存在；新增回归先失败、修复后6项全通过。最终同证书覆盖更新后，实际预检显示Full Disk Access Available，无需再次授权。

DR语义依据：[Apple TN2206](https://developer.apple.com/library/archive/technotes/tn2206/)。
