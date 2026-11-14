# 2026-11-14 重新编译打包

- 沿用 0.4.3（117），本次仅重新构建，不修改源码或递增版本。
- [build.log](build.log)：固定证书 release 构建完成；核心契约通过，264 项测试全部通过。
- [verification.log](verification.log)：App 结构、签名、语言、版本、烟雾测试及应用自检通过。
- [dmg.log](dmg.log)：重新生成 `build/SuperCleaner-0.4.3.dmg`，挂载检查签名、图标和 Applications 入口后卸载。
- [首次镜像日志](dmg-attempt-1.log) 记录系统“资源忙”；检查未发现本任务残留挂载，重新运行原脚本成功，未修改打包脚本。
- 新镜像验证通过后删除本次保存的旧镜像备份。未提交或推送，未替换 `/Applications` 安装副本。
- 后续推送前再次运行完整 `swift test`，264 项、0 失败，见 [prepush-test.log](prepush-test.log)。
