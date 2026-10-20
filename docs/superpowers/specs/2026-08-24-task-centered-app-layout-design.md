# Task-Centered App Layout Design

**Date:** 2026-08-24
**Status:** Approved direction A
**Scope:** Complete navigation, page hierarchy, naming, and contextual-action redesign for the macOS cleaner

> Historical context: this document preserves the rationale for the task-centered layout. The former separate preview step has since been removed; current safety comes from final confirmation and mandatory revalidation immediately before real execution.

## Problem

The current product exposes scanner modules and engine states as top-level product concepts. This causes four systemic problems:

1. The sidebar item `智能清理` contains another mode named `智能清理`, so page and strategy are indistinguishable.
2. `磁盘空间`, `开发工具`, and `Agent 工作空间` repeat the same search/list/inspector workbench even when their user jobs differ.
3. A global cleanup footer appears on unrelated pages such as application management, history, and settings.
4. Counts and engine classifications are repeated in page headers, hero cards, and footers, while the user's next action is less prominent.

The redesign must organize the product around user tasks, keep the Agent capability visible as a differentiator, and retain the existing safety model: read-only scanning, protected items, immutable plans, execution-time revalidation, quarantine, receipts, and restore.

## Design Principles

- A top-level destination names a user job; a control inside that page names a strategy or view.
- Each fact appears once at the level where it changes a decision.
- Primary flows are summary-first. Full paths and checkboxes remain available on demand.
- A page only displays actions relevant to that page.
- The engine recommends; users are not asked to judge unfamiliar system paths one by one.
- Protected, retained, and selected states use text and symbols in addition to color.
- Agent cleaning remains a distinct top-level capability, not the organizing principle for the whole product.

## Navigation

The sidebar contains seven destinations in two visual groups.

### Primary tasks

1. `概览` — scan entry and result hub.
2. `清理中心` — recommended, deeper, and manual general cleanup.
3. `应用卸载` — application-specific uninstall planning.
4. `大文件` — review large items found in Downloads and Desktop.
5. `Agent 环境` — clean reproducible Agent artifacts and inspect protected assets.

### Utilities

6. `恢复记录` — receipts and restore actions.
7. `设置` — permissions, privacy, safety, licensing, and updates.

`开发工具` is removed as a top-level destination. Developer caches remain a first-class category inside `清理中心`, primarily in the deeper plan and manual list.

## Global Shell

### Toolbar

- Show `扫描` only on `概览`, `清理中心`, `大文件`, and `Agent 环境`.
- `应用卸载` owns an application refresh action instead of the global cleanup scan.
- `恢复记录` and `设置` do not show scan actions.
- The sidebar toggle remains a native toolbar control.

### Cleanup action bar

- Show the plan action bar only on `清理中心`, `大文件`, and `Agent 环境`.
- Hide it on `概览`, `应用卸载`, `恢复记录`, and `设置`.
- The bar displays the global cleanup-plan total once, a short current-plan state, and the primary confirmation action.
- Confirmation performs no mutation. After confirmation, real execution independently revalidates the immutable plan before moving any item.
- Application uninstall keeps its separate plan sheet and never joins the general cleanup plan.

## Page Designs

### 1. 概览

#### Before scanning

- One title and one sentence explaining the scan.
- One primary `开始扫描` button.
- One compact trust row: `只读扫描`, `执行前复验`, `可恢复`.
- Remove duplicate product-capability marketing cards.

#### After scanning

- A single recommendation hero with recommended bytes/items and `查看推荐方案`.
- A secondary `重新扫描` action.
- An `其他可处理空间` section with three task cards:
  - `深度空间` — rebuildable/downloadable general and developer content.
  - `大文件` — large Downloads/Desktop items, never automatically selected.
  - `Agent 环境` — reproducible Agent output plus retained/protected assets.
- A compact `应用卸载` link is separate because application removal uses a different plan.
- Do not show the global cleanup action bar on the overview.

### 2. 清理中心

- The page title stays `清理中心` for all strategies.
- The segmented control label is `方案`; values are:
  - `推荐` — high-confidence, low-recovery-cost items.
  - `深度` — recommendation plus rebuildable/downloadable content with a clear cost statement.
  - `手动选择` — full list and inspector.
- The internal engine case may remain `smart/deep/custom`; user-facing copy must not say `智能清理` as a strategy.
- General cleanup scope includes caches, logs, temporary files, installers, and developer caches. It excludes large-file and Agent candidates.
- Recommendation and deep views show one hero total, grouped categories, retained total, and protected total.
- `手动调整` opens the detailed list; do not repeat counts in the page header.
- Manual rows keep a native checkbox and stable selected-row highlight. The inspector explains why found, recommendation, impact, retention, restoration, and execution-time revalidation.

### 3. 应用卸载

- Preserve the native selected-row highlight and right-side inspector.
- Add search by application name or Bundle ID.
- Add one filter with `全部`, `可卸载`, `运行中`, and `系统保护`.
- The inspector owns the only primary action: `查看推荐卸载计划`.
- The plan preselects the application bundle and exact, recoverable, non-shared associations.
- User data, shared containers, running apps, and system apps remain protected.
- No global cleanup action bar appears.

### 4. 大文件

- Rename `磁盘空间` to `大文件` to match current capability.
- Subtitle explicitly says `下载与桌面中的大型项目，仅供审查，不会自动选择`.
- Use a two-pane list and inspector.
- Keep search, remove the generic recommendation filter because every item starts retained, and add size ordering if needed.
- Selecting a row only inspects it. Checking it adds the exact path to the cleanup plan.
- The contextual cleanup action bar is visible.

### 5. Agent 环境

- Replace raw Skills/MCP headline counts with decision-oriented totals:
  - `可释放空间`
  - `默认保留`
  - `始终保护`
- Provide two views:
  - `清理建议` — summary-first, grouped reproducible output such as model/package cache, completed sandboxes, and completed worktrees.
  - `环境资产` — detailed list and inspector for Skills, MCP, sessions, configuration, credentials, knowledge, and protected roots.
- `清理建议` never lists thousands of protected files by default. When no safe Agent output exists, say so explicitly and keep assets protected.
- `环境资产` supports search and recommendation/category filtering.
- The contextual cleanup action bar is visible only when viewing Agent cleanup content; it must never imply that protected assets are selected.

### 6. 恢复记录

- Rename `操作历史` to `恢复记录`.
- Empty state explains that completed quarantine operations appear here.
- Receipt rows show date, result, moved item count, bytes, and restore availability.
- Restore conflicts remain non-overwriting and are explained near the action.
- No scan toolbar item and no cleanup action bar appear.

### 7. 设置

- Rename `设置与权限` to `设置`.
- Keep configuration grouped by permission, safety, and update purpose.
- Each permission row shows state, consequence, and its own action.
- Do not expose inactive telemetry or diagnostic-sharing controls.
- No scan toolbar item and no cleanup action bar appear.

## State And Interaction Rules

- Scanning from the overview transitions to `清理中心` in the `推荐` strategy when complete.
- Changing recommendation strategies deterministically rebuilds the general-cleanup selection and invalidates any pending plan.
- A manual checkbox change switches the general-cleanup strategy to `手动选择` and invalidates the pending plan.
- Cross-module selections are never hidden by a strategy change: choosing `推荐` or `深度` resets the current cleanup plan to that explicit scope.
- Row focus and checkbox selection remain separate concepts.
- Filters reconcile focus to the first visible row without changing selection.
- Uninstall selection remains isolated from the general cleanup selection.

## Copy Contract

- Do not use `智能清理` as both destination and strategy.
- Use `推荐`, `深度`, and `手动选择` for strategies.
- Use `推荐清理`, `深度清理`, `默认保留`, and `始终保护` for item dispositions.
- Use direct confirmation language for the non-mutating checkpoint, and describe the following operation honestly as real execution.
- Replace `0 KB` with `< 1 KB` when bytes are non-zero but format below one kilobyte.
- A checked box means `加入当前计划`; it does not mean the user has independently certified safety.

## Accessibility Contract

- Native list selection must expose a selected state.
- Checkbox labels are dynamic: `加入计划`, `从计划移除`, or `始终保护`.
- Every status combines text with an SF Symbol; color is supplemental.
- Segmented controls, lists, checkboxes, filters, and primary actions remain keyboard accessible.
- Page titles precede controls in accessibility reading order.
- Long lists use native virtualization and do not require pointer-only interactions.

## Safety Invariants

- Scanning and confirmation perform zero writes.
- Blocked candidates cannot become selected through UI or state restoration.
- Execution revalidates path policy, identity, active state, rule version, and plan expiry.
- Cleanup moves items to quarantine and records receipts; it does not silently permanently delete.
- Restore never overwrites an existing path.
- Agent credentials, knowledge, configuration, Skills, MCP definitions, active sessions, source code, and protected roots are retained or blocked unless a future explicit rule proves a narrower item reproducible.
- Application user data and shared containers remain blocked.

## Verification

Completion requires all of the following evidence:

1. Core contracts pass for navigation naming, cleanup scope, mode selection, blocked-state enforcement, recursive byte measurement, uninstall recommendations, execution-time revalidation, execution, and restore.
2. The release app and helper build and sign through `Scripts/build-app.sh`.
3. Source search finds no obsolete user-facing destination titles or duplicated `智能清理` strategy copy.
4. Computer Use verifies all seven sidebar destinations, both Agent views, all three cleanup strategies, application search/filter/selection, contextual action-bar visibility, and accessibility labels.
5. Fresh screenshots are captured and inspected for every destination and important substate.
6. No actual cleanup, uninstall, permission grant, or restore is performed during UI verification.

## Out Of Scope

- A full-disk treemap or storage-category engine.
- Permanent deletion or automatic Trash emptying.
- New visual branding, custom iconography, or a new color system.
- Cloud synchronization, accounts, subscriptions, or telemetry enablement.
