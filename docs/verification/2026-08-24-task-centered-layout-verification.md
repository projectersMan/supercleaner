# Task-centered layout verification

Date: 2026-08-24  
Historical branch: interaction-safety-workbench

## Acceptance matrix

| Destination | Verified responsibility | Global scan | Plan action bar | Result |
| --- | --- | --- | --- | --- |
| 概览 | Pre-scan explanation and post-scan task routing only | Yes | No | Pass |
| 清理中心 | Recommended, deep, and manual strategies | Yes | Yes | Pass |
| 应用卸载 | Search, status scope, refresh, selection, details, separate uninstall plan | No | No | Pass |
| 大文件 | File-value review with name/path and selected filters only | Yes | Yes | Pass |
| Agent 环境 | Cleanup recommendations separated from environment assets | Yes | Cleanup view only | Pass |
| 恢复记录 | Receipts, moved count, bytes, restore availability, non-overwrite explanation | No | No | Pass |
| 设置 | Permissions, privacy, safety, licensing, and updates | No | No | Pass |

## Interaction checks

- Sidebar contains exactly five primary tasks and two utilities; removed duplicate Developer Tools destination.
- Cleanup Center switches between `推荐`, `深度`, and `手动选择`; no nested `智能清理` naming collision remains.
- Application list selection is visibly highlighted and drives the inspector.
- Application search for `ChatGPT` filters the list and reconciles the inspector to the first visible result.
- Large Files exposes only search and selected-only filtering.
- Agent Environment switches between `清理建议` and `环境资产`; the asset view has no cleanup plan bar.
- Navigating away from Cleanup Center clears transient strategy status instead of leaking it into Large Files or Agent Environment.
- Cleanup, Large Files, and Agent execution plans are scoped to their current destination.
- Toggle accessibility labels describe the next action and change between adding and removing an item.
- No destructive UI action was triggered during acceptance. No confirmation, quarantine, uninstall, restore, permission grant, or settings change was performed.

## Visual checks

Fresh screenshots are stored outside the repository at:

`/Users/bytedance/.codex/visualizations/2026/08/24/01a032f6-a9c4-7e12-9e87-e48b62098fbe/task-centered-acceptance`

Reviewed at the same 1200 × 768 app window size for title hierarchy, spacing, toolbar ownership, selection highlight, card density, empty states, and footer visibility.

## Automated checks

- `./Scripts/build-app.sh` builds CleanerCore, CoreContractChecks, CleanerApp, and CleanerHelper.
- Core contracts cover navigation policy, cleanup strategy names, page scoping, overview summary, Agent summary, application filtering and selection reconciliation, byte formatting, and dynamic selection labels.
- Source audit rejects obsolete destination and action terminology, including `智能清理`, `自定义清理`, `操作历史`, `设置与权限`, and `smartCleanupCandidates`.

## Observed limitation

One real read-only scan remained active for more than one minute before the Mac locked. The UI stayed responsive, offered cancellation, and continued to state that no files were being modified. Scan completion time should be benchmarked separately against large Agent environments before commercial release; this verification does not claim a completed full-disk scan.
