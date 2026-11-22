# 自适应目录分组验证

日期：2026-11-22。

- `tests.log`：Debug 全量 356 Core + 20 App 测试通过。新增九项分组回归覆盖密集分支、单链、稀疏目录、推荐去重、搜索稳定、路径边界、无组数限制和不同主目录分支隔离。
- `make-fixture.py`：使用 Python 标准库生成独立的模型联测文件，全部位于本目录的 `home`。同内容副本、可完整匹配的 ZIP 和安装包用于现有应用自检。
- `model-check.log`：真实扫描 → 推荐分组 → 手动选择 → 重复范围 → 保留件失效 → 设置刷新联测通过。
- `build.log`：标准发布构建、Release 全量测试、核心契约与打包门禁。
- `verify-app.log`：打包应用结构、稳定签名、启动与既有流程自检。
- `release-model-check.log`：最终应用中再次运行分组与实际扫描联测。
- `package.log`：DMG 生成记录。

复现真实扫描联测：

```sh
python3 Tests/large-file-directory-groups/make-fixture.py
SUPERCLEANER_DUPLICATE_FIXTURE="$PWD/Tests/large-file-directory-groups/home" .build/debug/CleanerApp --scan-cleanup-self-check
```

ZIP 素材必须满足原扫描规则：归档自身超过阈值，匹配文件夹总量同时大于阈值和归档大小。最初纯随机素材压缩后略大于原始文件，不能满足该规则；改成随机数据与可压缩尾部后通过。未修改识别或安全规则来迁就素材。

详情和逐文件理由见 [分组说明](../../doc/large-file-directory-groups.md)。合成二进制文件在验证后删除，保留可复现生成脚本；没有操作用户真实文件。

最终 0.5.21（166）发布构建、应用验证、包内扫描联测及 DMG 校验均通过。合成 `home` 和打包临时目录已清理。没有替换用户已安装应用或执行真实文件清理。
