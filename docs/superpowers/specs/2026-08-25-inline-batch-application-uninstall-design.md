# Inline Batch Application Uninstall Design

Date: 2026-08-25

## Goal

Make application uninstall analysis a product of the system scan rather than a button-triggered action. Present each application's uninstall scope directly in the application list, allow inline per-item adjustment, and execute multiple selected applications as one recoverable batch.

## Product decisions

- The page no longer has a selected-application inspector, a “查看推荐卸载计划” button, or an uninstall-plan sheet.
- The application module analyzes uninstall scope independently of row selection.
- Every application row remains compact by default and can expand in place to show concrete uninstall items.
- No application is selected for removal by default. Scanning never implies uninstall intent.
- Selecting an application selects only its recommended, non-protected uninstall items.
- Protected, shared, user-data, system, running, unverifiable, and path-policy-blocked items cannot be forced into a batch.
- Multiple applications and their selected child items execute as one quarantine-backed cleanup plan.

## Page structure

The current split view becomes one full-width hierarchical list.

Each collapsed row contains:

1. Application-level checkbox or protection icon.
2. App icon, name, version, and Bundle ID.
3. Running/system/available state.
4. Analysis coverage: complete, limited, unavailable, or protected.
5. Recommended item count and estimated removable bytes.
6. Disclosure control for inline details.

Expanding a row reveals:

- Application bundle and precisely attributed associated files.
- One checkbox per selectable item.
- Ownership evidence, size, and “建议移除 / 已保留 / 始终保护” status.
- A concise protection boundary for user data and shared containers.

A persistent batch bar at the bottom shows selected application count, selected item count, estimated bytes, and one primary action: “移动所选项目到隔离区”. The action remains disabled until at least one valid item is selected. Execution still performs dry identity/path/activity validation and writes a recovery receipt.

## Scan architecture

### Application uninstall inventory

The applications module returns an `ApplicationUninstallInventory` containing:

- the installed application inventory;
- one `ApplicationUninstallAnalysis` per discovered application;
- explicit per-application coverage and any limitation message;
- concrete `UninstallPlan` data for successfully analyzed applications.

System and running applications receive terminal protected analyses without traversing removal candidates.

### Avoiding repeated work

Association roots such as Caches, Preferences, Containers, and Application Support are enumerated once per system scan. Entries are indexed by normalized Bundle ID/name boundaries and then assigned to applications. The scanner must not list the same association root once per application.

Application bundle sizing uses bounded traversal with shared scan accounting. Analysis has bounded concurrency and observes cancellation. Reaching a per-application or module budget produces a visible limited result rather than silently claiming completeness.

### Report propagation

`SystemScanReport` stores the uninstall inventory with the application module generation. Refreshing applications replaces both the app list and uninstall analyses atomically. The UI reads this report directly and never creates a plan because a row was selected.

## Selection model

Introduce a pure `UninstallBatchSelectionState` keyed by uninstall item candidate IDs.

- App selection state is none, partial, or all across that app's selectable recommended IDs.
- Toggling an app with none/partial selects all recommended IDs; toggling all clears them.
- Toggling a child affects only that child.
- Protected items are excluded from selection calculations.
- Batch summary deduplicates candidates by standardized path and reports application count, item count, and bytes.
- A scan-generation change clears the batch selection.

The same tri-state and persistent batch-bar language is shared with cleanup center, large files, and Agent Environment. This phase does not rewrite their already-working selection stores; it extracts reusable presentation where doing so removes duplication.

## Execution and lifecycle

The batch executor flattens selected items from all analyzed applications into one `CleanupPlan`. `CleanupExecutor` continues to validate each item immediately before moving it. The resulting receipt is registered with the current quarantine retention policy, so restore, automatic deletion, and manual purge behave exactly like other cleanup batches.

After execution, the application module refreshes. Applications whose bundles were moved disappear; failed or skipped applications remain with updated analysis. Partial execution is reported explicitly.

## Loading and failure states

- During the application scan, the module progress says it is discovering and analyzing uninstall scope.
- A row whose analysis is limited or unavailable remains visible and explains why.
- Failure of one application analysis does not erase the rest of the module.
- Rapid filtering or expansion performs no filesystem analysis and cannot race results between applications.
- Empty analysis means “no safely attributable associated items”; it does not mean the app was not scanned.

## Accessibility and interaction

- Clicking anywhere on the row focuses it; disclosure and checkbox retain separate accessible actions.
- Application and child selection expose none/partial/all state in VoiceOver labels.
- Status is never conveyed by color alone.
- Keyboard users can move through rows and expand/collapse without opening another window.

## Verification

Core contracts must prove:

- uninstall analysis exists before any UI selection;
- protected/running/system applications never contribute selectable IDs;
- app-level tri-state selection and child overrides are deterministic;
- batch flattening deduplicates paths and preserves multiple application ownership counts;
- one failing or budget-limited analysis does not discard successful analyses;
- the combined batch still rejects forged/protected paths through the existing executor contracts.

UI verification must prove:

- no inspector button or uninstall sheet remains;
- rows show uninstall summaries without being selected;
- expanding reveals child items in place;
- selecting two applications updates the batch bar and produces one execution confirmation path;
- no destructive action is invoked during visual verification.
