# Guided Cleanup Modes Design

Date: 2026-08-24
Status: Approved for direct implementation

> Historical context: this design records the recommendation-mode work. The current implementation has removed the separate preview report and now relies on final confirmation followed by mandatory execution-time revalidation.

## Problem

The current product exposes the engine's conservative `safe / review / blocked` classification directly as a user decision. Because most directories are `review`, the interface repeatedly says “需要确认” while offering only a checkbox. This is technically cautious but cognitively expensive. Application Management also uses a non-selecting list, so clicking an application gives no persistent highlight or explanatory context.

## Product Principle

The engine owns routine decisions. The user confirms one bounded plan, not dozens of filesystem facts they cannot reasonably judge. Uncertainty is handled by retaining or protecting an item, not by forcing a novice to guess.

Safety invariants remain unchanged: protected paths cannot be selected, confirmation performs no mutation, execution uses immutable plans and revalidates identity/activity/rules/expiry, and all removal is recoverable through quarantine.

## Cleanup Modes

### Smart Cleanup

Default mode. Select only candidates with high-confidence `recommended` disposition. Show a compact category summary rather than the full path list. Display how much the engine recommends, how much it retained, and how many items it protected. The primary action opens one final plan confirmation; accepted plans proceed to real execution with fresh safety checks.

### Deep Cleanup

Adds candidates with `deepClean` disposition: rebuildable or downloadable content whose recovery has a time/network cost. It never includes user knowledge, credentials, configuration, sessions, worktrees, large user files, application-support data, active items, or blocked candidates. The UI explains the trade-off once at mode level.

### Custom Cleanup

Shows the existing searchable workbench and independent checkboxes. Labels describe system recommendations:

- `推荐清理` for high-confidence automatic candidates.
- `深度清理` for rebuildable candidates included only in Deep mode.
- `默认保留` for ambiguous or context-bearing candidates.
- `始终保护` for blocked candidates.

Checking a selectable item means “include this item in the plan”; it is not a separate confirmation ceremony.

## Recommendation Policy

Introduce a pure `CleanupRecommendationPolicy` in CleanerCore. It maps a candidate to:

- `recommended`: selectable `safe` candidates.
- `deepClean`: inactive `review` candidates in cache, log, temporary-file, installer-artifact, developer-cache, agent-model-cache, or agent-package-cache categories.
- `retain`: every other selectable `review` candidate.
- `protected`: blocked candidates.

Mode selection is deterministic:

- Smart selects `recommended`.
- Deep selects `recommended + deepClean`.
- Custom preserves explicit user selection.

Changing mode replaces selection with that mode's recommendation and invalidates any pending plan. Destination and visual filters never change the plan.

## Simplified Smart/Deep UI

Smart Cleanup and Deep Cleanup use a summary-first screen:

- segmented mode picker: `智能清理 / 深度清理 / 自定义`;
- recommended item/space total;
- grouped category rows with item count, bytes, and plain-language reason;
- compact disclosures for retained and protected counts;
- one optional “查看项目” transition to Custom mode;
- the existing bottom action bar remains the single action surface.

Developer Tools and Agent Workspace retain the workbench because they are specialist destinations, but adopt the new recommendation labels.

## Application Management

Use native `List(selection:)` with a selected application ID. Clicking a row highlights it and opens a right-side inspector showing name, version, Bundle ID, running/system protection, and the single “检查卸载建议” action.

The uninstall planner preselects the application bundle and exact non-user-data, non-shared associations. User-data and shared associations remain blocked. The sheet uses `建议移除 / 已保留 / 始终保护`, shows a plan summary, and asks for one final action. It must not describe every selectable item as “需要确认”.

## Accessibility

Mode picker, application list selection, recommendation badges, and plan checkboxes have separate semantics. Row selection changes inspection focus only. Checkboxes change plan membership only. State must not rely on color alone.

## Verification

- Core contracts prove recommendation mapping and mode selection.
- Application contracts prove uninstall defaults include exact owned items and exclude protected user/shared data.
- Release build and current CoreContractChecks pass.
- GUI acceptance verifies mode simplification, application highlight/detail, one-plan confirmation, AX separation, and pending-plan invalidation.
- GUI acceptance never performs real cleanup or uninstall.
