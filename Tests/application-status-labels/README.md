# 应用状态短标签核对（0.2.40 / 73）

用户要求删除名称旁绿色Running标记，并将System protected缩短为Protected。仅修改视图及共用本地化短标签，不改筛选、扫描或执行规则。

Release编译、1014条双语检查及本批逐处diff通过；未运行测试套件。原有ApplicationUpdateModel弱引用捕获警告未扩大修复。

最终安装副本实机核对：
- 扫描前FDA Available，不需重新授权。
- 初始Uninstallable，22/94项。
- Running 8/94项，名称旁无绿色圆点或Running；右侧橙色Running · Cannot uninstall yet及锁定保持。
- Protected 65/94项，筛选和行徽标均为Protected，工具条固定尺寸保持。
- 核对后恢复Uninstallable，无卸载选中或执行操作。Agent为此次只读UI核对不需要的模块，已取消，不声称完成完整Agent分析。

App/安装副本/DMG版本、123项内容及签名一致，见[package-verification.txt](package-verification.txt)。镜像已卸载，临时材料清理，未提交或推送。
