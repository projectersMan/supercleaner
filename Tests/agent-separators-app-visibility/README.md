# 分隔线与应用可见性核对

用户要求Agent行分隔，并报告若干应用找不到。修正前，实际0.2.38库存94项，默认Uninstallable仅显示22项。切换All逐个搜索，截图全部六个应用都存在，且均Running：

| 应用 | Bundle ID | 结果 |
| --- | --- | --- |
| ChatGPT | com.openai.codex | Running，锁定卸载 |
| Google Chrome | com.google.Chrome | Running，锁定卸载 |
| 飞书 / Lark | com.electron.lark | Running，锁定卸载 |
| 飞连 / CorpLink | com.volcengine.corplink | Running，锁定卸载 |
| TRAE CN | cn.trae.app | Running，锁定卸载 |
| Amphetamine | com.if.Amphetamine | Running，锁定卸载 |

本批Agent Skill/MCP行加入与大文件同一1pt/secondary 0.12底部分隔线，不改选择或Top3。曾准备将应用范围初值改All，用户随后要求保持默认可卸载，已撤销该行。最终仍为Uninstallable；非All搜索空结果增加范围说明，不改扫描或筛选规则。

同批中间包实机已确认：All 94/94，Chrome在Uninstallable为0且显示新范围说明，切换All为1且保持运行保护；Agent扫描生成980项Skill/45份MCP后，两种列表截图均确认1pt横线，包含白色行和悬停浅蓝背景，未更改勾选。最终默认范围修正版release编译通过，沿用0.2.39（72）和固定证书重新打包。没有执行自动测试套件或文件删除。

包证据见[package-verification.txt](package-verification.txt)，最终修正版已覆盖安装，三份包123项文件/链接一致，App/Helper 0.2.39（72），默认属性为Uninstallable。最终重新启动并确认版本后停留清理中心，未再启动整轮扫描；分隔线实机检查对应最终未变的Agent视图代码。
