# Cleanup Navigation and System Cleanup — Design QA

## Comparison target

- Source visual truth: `/var/folders/n7/rfx22y011135xh0knrq2h8rc0000gn/T/codex-clipboard-e288369a-c4c7-44e2-a299-8251ae64ef67.png` (2000 × 1239 px), used for the light single-column scan/result rhythm, disclosure rows, selection controls, and generous spacing.
- Navigation truth: `/var/folders/n7/rfx22y011135xh0knrq2h8rc0000gn/T/codex-clipboard-590113a7-3eba-4b07-bfbe-b7db7f5f6511.png`, used for the current sidebar and live-scan state. The requested System Cleanup destination is inserted directly below Cleanup Center.
- Implementation: `/Users/bytedance/Documents/ChatGPT/moleapp/build/SuperCleaner.app`.
- Implementation screenshot: native CUA full-window capture attached inline to this task (1350 × 768 px; the native capture API did not expose a filesystem path).
- Viewport/state: 1350 × 768 macOS window, light appearance, live full scan with progressively completed dimensions and Agent Environment scanning.
- Density normalization: source imagery and native capture were compared as full-window compositions at fitted display scale; no pixel-perfect density claim is made because the references use different window sizes.

## Findings

- P0: none.
- P1: none.
- P2: none remaining.
- P3: the scan progress panel retains a subtle grouped background instead of the reference's completely white field. This preserves native macOS grouping and does not change the requested hierarchy or density.

## Required fidelity surfaces

- Fonts and typography: native macOS system typography is retained. The title, section labels, secondary copy, and status labels follow the same descending hierarchy as the reference without introducing a custom typeface or wrapping regression.
- Spacing and layout rhythm: the scan screen uses a wide header followed by four persistent dimension rows. Cleanup categories, application rows, and large-file rows use lightweight separators rather than stacked cards. Cleanup Center and System Cleanup are adjacent in the sidebar. The former post-scan card summary is no longer part of the flow.
- Primary-action placement: destructive and cleanup actions use the fixed bottom action bar, aligned to the trailing edge. Cleanup Center's 一键清理 now occupies the same position as 系统清理、应用卸载、大文件 and Agent 环境 actions; scan/cancel/refresh controls remain in page context because they are not cleanup commits.
- Colors and visual tokens: the interface keeps native semantic foreground/background colors and the existing green, blue, orange, and purple module accents. Agent Environment remains purple as shown in the navigation reference.
- Image quality and asset fidelity: all visible UI icons are native SF Symbols; no placeholder, CSS art, improvised glyph, or rasterized icon replacement was introduced.
- Copy and content: sidebar labels are “清理中心 / 系统清理 / 应用卸载 / 大文件 / Agent 环境”. All user-facing “通用清理” labels were renamed to “系统清理”. Scan-required copy points back to 清理中心. Each dimension displays its scan state plus default-cleanup state before, during, and after execution. Existing safety, selection, deletion, and recovery language is retained.
- Default-selection hierarchy: System Cleanup's “自动清理” plan is the one-click scope and includes recommended plus explicitly rebuildable cleanup categories. Application one-click cleanup includes exact Bundle-ID caches and conservatively matched product-prefixed caches for inactive apps, never the app bundle, shared content, or user data. Agent defaults remain safe, inactive, and recommended; Large Files still requires an explicit safe classification. Matching items are checked automatically and sorted before unselected items.

## Interaction and accessibility evidence

- Opened 清理中心 and 系统清理, verified their distinct selected states, and verified the pre-scan action returns from 系统清理 to 清理中心.
- Started a real read-only full scan and verified the UI remained in 清理中心 while progressive module results arrived.
- Verified completed module rows remain navigable, scanning rows show progress, and 取消扫描 remains available.
- Verified 一键清理 becomes enabled as soon as the first dimension completes instead of waiting for the whole scan, while the other dimensions continue scanning.
- Verified 一键清理 is no longer rendered beside 取消扫描 in the hero. Native full-window capture shows it fixed at the bottom-right while the four dimensions continue scanning.
- Opened 大文件 and confirmed its confirmation action uses the same bottom action-bar slot; the shared `SelectionActionBar` keeps right alignment and spacing consistent across cleanup pages.
- Verified default-selection contracts across System Cleanup, Applications, Large Files, and Agent Environment. System automatic-cleanup fixtures enter the one-click plan; application defaults include only exactly-owned inactive-app caches; running-app caches and protected/user/shared items stay excluded.
- Verified Large Files still has no explicitly safe candidate and remains unselected; review-only large files are not promoted merely to create a default selection.
- Post-adjustment live scan verified System Cleanup selected 78 automatic-cleanup items (about 3.56 GB) and Applications selected one inactive Brave Browser cache item (about 7.1 MB). The selected application moved to the top of the app list, and 一键清理 remained enabled while Agent scanning continued.
- Opened System Cleanup and verified its segmented control contains only “自动清理 / 手动选择”; 自动清理 is selected and its 78-item plan matches the system portion of 一键清理.
- Verified the four-row status surface remains in place after completed results arrive; the old “扫描完成，结果已统一汇总” card screen is not shown.
- Verified default policy contracts: System Cleanup includes only recommended items; Agent Environment includes only recommended, safe, inactive items; Applications and Large Files default to retain/manual choice.
- Verified the selection action bar is not shown during scanning, preventing disabled cleanup controls from competing with scan progress.
- Checked the accessibility tree for stable selected-row state, button labels, section names, and destination order.
- Confirmed cleanup actions describe a real operation: the confirmation itself is non-mutating, and accepted plans are revalidated immediately before files are moved.

## Current implementation boundary

- The embedded Helper target and authorization protocol are an implementation skeleton; the current App does not install, connect to, or invoke it.
- The signed `RuleStore` is independently implemented and tested, but it does not currently supply rules to the scan pipeline.
- The locally inspected app uses ad-hoc signing for development verification only. This evidence does not claim Developer ID signing, notarization, or release readiness.

## Comparison history

1. Earlier direction introduced an extra internet dimension and removed the existing tools area. The user clarified that the four current top-level dimensions and tools/settings must remain; that direction was fully removed before the final build.
2. First native interaction pass found that a progressive partial report could replace the scan progress screen. Fixed by keeping 清理中心 on the scan screen for the entire scanning phase; post-fix evidence showed module progress and cancellation controls throughout the scan.
3. The live-scan comparison showed a disabled cleanup action bar below progress. Fixed by hiding the plan bar while scanning; it returns after scanning with all selection and execution behavior intact.
4. The completed scan previously replaced the live module list with a separate card summary. Removed that branch and kept the same four dimension rows as the continuous scan/cleanup status surface.
5. Added progressive 一键清理 availability. A completed dimension can be checked or cleaned immediately; later dimensions become eligible as their own scans finish, and each row reports its cleanup state independently.
6. Moved 清理中心's primary cleanup action from the hero to the shared bottom-right action region, matching every other cleanup destination without changing cleanup behavior.
7. Added default selections for every dimension and prioritized selected categories, apps, files, Agent resource groups, and individual Agent assets at the top of their respective lists.
8. Removed the extra “安全清理” system-cleanup mode. “自动清理” is again the default and now exactly matches the system portion of 一键清理; inactive applications contribute exact Bundle-ID or conservatively matched product-prefixed cache directories to one-click cleanup.

## Follow-up polish

- P3 only: if closer visual mimicry is desired later, the scan module panel background can be reduced further after checking contrast in both light and dark appearance.

final result: passed
# 清理结果状态口径（2026-09-09）

- 一键清理执行过但未成功删除的项目会退出默认队列，避免再次点击后重复重试。
- 未自动处理的项目按系统、应用、大文件、Agent 环境分别显示橙色“待手动清理”状态。
- 同一维度同时存在成功项和手动项时，状态完整显示“已清理项数 + 已释放容量”和“待手动项数 + 待处理容量”；容量按实际大小使用 KB、MB 或 GB。
- 清理中心在“重新完整扫描”附近显示本次 App 启动以来成功清理的累计项数和容量；重新扫描不会清零该会话统计。
- 会话累计统计覆盖一键清理、维度内手动删除与应用卸载，只计入实际成功隔离、移入废纸篓或永久删除的结果。
- Agent 环境仅保留平台选择，平台内始终展示全部可清理范围和类型，不再为两个“全部”筛选器保留独立空间。
- Agent 类别整行可单击展开或折叠，复选框继续只控制该类别的清理选择。
