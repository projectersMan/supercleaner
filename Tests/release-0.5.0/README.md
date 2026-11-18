# 0.5.0 发布验证

用户明确要求版本升级为 0.5.0，并提交、推送自上次提交以来全部工作。基点为 `1062a42d4aeeb94f9734e6acea794747cc89cbbf`，本地与远程 main 在开始时一致。

## 本轮逐文件修改理由

| 文件 | 修改及必要性 |
| --- | --- |
| [Scripts/version.py](../../Scripts/version.py) | 显式 next-build --version 精确使用目标版本，拒绝同版、降级和非法格式；保留常规 patch 与 build 单调递增、环境一致性和原子保存。 |
| [Scripts/build-app.sh](../../Scripts/build-app.sh) | 将显式版本参数传至唯一版本工具，避免指定 0.5.0 被再次递增为 0.5.1；App/Helper 共用分配结果。 |
| [Tests/test_version.py](../test_version.py) | 两项新回归先红后绿，验证精确版本、非法目标不写入、构建号和后续普通递增；共 13 项。 |
| [.gitattributes](../../.gitattributes) | 复用现有 Git LFS 管理版本化 DMG，避免把大型二进制直接存入普通 Git 对象；原始测试日志保留工具输出的空白，不参与源码空白规则。 |
| [Version.json](../../Version.json) | 由正式构建一次分配 0.5.0（145）。 |
| [README.md](../../README.md) | 更新当前用户安装包和显式版本构建用法。 |
| [doc/architecture.md](../../doc/architecture.md)、[docs/architecture.md](../../docs/architecture.md) | 记录精确发布版本与常规递增共用入口，保持元数据一致。 |
| [doc/development.md](../../doc/development.md)、[docs/development.md](../../docs/development.md)、[发布清单](../../docs/production-release-checklist.md) | 替换手动修改版本仍被加 patch 的旧说明，补充显式目标与 CI 一致性。 |
| [发布记录](../../doc/release-0.5.0.md) | 汇总自上次提交以来的最终行为与产物入口，保留旧版本历史验证边界。 |
| 本目录 | 记录版本测试、完整编译、包验证、签名、DMG 与独立发布审查证据。 |

前序全部源码更改的逐文件必要性和审查边界见 [独立审查](review.md)，各专项历史记录保留在对应 Tests 目录。

局部建议：显式发布使用同一分配入口，100/100，已实施。全局建议：源码版本、App/Helper、DMG 与远程产物共用同一次构建并核对哈希，99/100，本轮执行。未引入依赖；主体为 Swift，Python 工具仅使用标准库。

## 验证

- [版本新增回归红灯](version-red.log)：13 项中新增两项失败，证实旧入口无法精确指定发布版本。
- [版本回归绿灯](version-green.log)：13 项通过，包括非法目标不写入。
- [完整编译](package.log)：0.5.0（145）分配恰好一次；318 项 Release XCTest、1272 条双语校验、Core contracts、固定模型及稳定签名门禁通过。
- [包内验收](verification.log)：导航、资源列表、默认队列、Trash 并发/失败/抑制/退出等自检及实际 SDK 27.2、最低 macOS 13.0 校验通过。
- [关闭提醒源码检查](trash-source-check.log)、[真实 NSWindow / NSAlert 回归](trash-dialog-native.log)、[真实 NSApplication 终止回归](trash-quit-native.log)通过。原生素材由 zsh 运行，执行器禁止真实 Finder 清空；生成的中间 App 与抽取源码已清理。
- [DMG 制作](dmg.log)、[挂载核对](artifact-check.log)、[产物摘要](artifact-check.json)通过，App/Helper 版本、稳定签名、Apple Events entitlement 及三个可执行文件哈希一致。
- [构建输入核对](source-hash-check.log)：246 个代码/资源输入构建后无变化；排除 Finder 自动改变的 .DS_Store 元数据。
- [独立审查](review.md)无已证实的 Critical/Important 问题，列出全部源码修改的逐文件理由。


未替换当前运行的安装、未执行真实 Finder 清空、未修改权限或注册 Helper。安装包纳入 Git LFS；本轮仅推送仓库内容，不创建公开更新渠道发布。

DMG：299,014,026 字节；SHA256 `b2a1281026ddf0949902c998f0d1e4eb6e037ede95c2d6ced3ac0e60efb5cdfe`。正式构建、验证和打包后的版本配置均为 0.5.0（145），原 `/Applications` 安装仍为 0.4.29。

提交前额外整理：历史原始日志包含 hdiutil 列对齐和 diff 上下文空白，保留原文并通过 .gitattributes 排除日志空白检查；修正 Tests/cleanup-center-resource-sync/README.md 的单处多余尾空行。未改动这些历史日志的执行内容。
