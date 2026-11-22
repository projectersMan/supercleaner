# 目录控件验证

- `tests.log`：Debug 全量 356 Core + 21 App 测试通过，覆盖保护/不可读/组外候选排除与现有分组回归。
- `model-check.log`：真实扫描后的全选、取消、partial 补齐、搜索隐藏保留、手动组与推荐组隔离通过。
- `build.log`：标准发布构建、Release 测试及核心契约记录。
- `verify-app.log`：最终应用结构、签名、启动与既有流程自检。
- `release-model-check.log`：最终包内实际扫描与目录选择联测。
- `package.log`：DMG 生成记录。
- `context-menu-tests.log`：加入右键菜单后的全量测试。
- `context-menu-build.log`：0.5.24（169）发布构建、Release 测试和签名门禁。
- `context-menu-verify-app.log`、`context-menu-package.log`：最终应用自检和 DMG 生成记录。
- `remove-top-controls-tests.log`：移除顶部控制后的全量测试。
- `remove-top-controls-build.log`、`remove-top-controls-verify-app.log`、`remove-top-controls-package.log`：0.5.25（170）构建、应用自检和安装包记录。
- `select-all-tests.log`：重复大文件全选/取消全选、partial 状态、All/Duplicate 与搜索范围联测；记录 Core 既有时序测试的环境失败。
- `select-all-build.log`、`select-all-verify-app.log`、`select-all-package.log`：0.5.27（172）构建、应用自检和安装包记录。
- `deduplicate-summary-tests.log`：去除筛选栏重复总数后的定向测试记录。
- `deduplicate-summary-verify-app.log`：0.5.28（173）打包应用结构、签名和只读自检记录。

复用 [合成素材脚本](../large-file-directory-groups/make-fixture.py)，生成文件全部在 `Tests/large-file-directory-groups/home`，不读写用户文件。执行后清理合成数据，保留脚本和日志。

```sh
python3 Tests/large-file-directory-groups/make-fixture.py
SUPERCLEANER_DUPLICATE_FIXTURE="$PWD/Tests/large-file-directory-groups/home" .build/debug/CleanerApp --scan-cleanup-self-check
```

说明与逐文件复核见 [目录控件](../../doc/large-file-directory-controls.md)。

0.5.24（169）DMG 已只读挂载，核对版本与严格签名后卸载。未替换用户已安装应用或执行真实清理。

0.5.25（170）移除顶部控制，保留右键目录菜单；DMG 已只读核对版本与严格签名。未替换用户已安装应用或执行真实清理。

0.5.27（172）增加重复大文件筛选栏全选三态控件；当前可见范围内的全选、取消、partial 和安全边界通过。App 22/22 通过；Core 的既有大文件时序测试仍失败，未修改 Core 执行逻辑。未替换用户已安装应用或执行真实清理。

0.5.28（173）移除筛选栏重复总文件数，仅保留 Select All 摘要中的单一计数。未执行真实清理。

最终 0.5.22（167）Debug、Release 各 377 项测试通过；包内联测、应用自检及安装包版本/严格签名核对通过。合成测试数据与打包临时目录已清理。
