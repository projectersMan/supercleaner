# Inline Batch Application Uninstall Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce uninstall analysis during the application scan and replace the selected-app inspector/sheet with a full-width inline, expandable, batch-uninstall list.

**Architecture:** Add an application uninstall analysis inventory to the shared scan report, discover association ownership once per scan, and model batch selection as a pure tri-state value. The SwiftUI page renders scan-owned summaries and child items directly; one combined `CleanupPlan` executes all selected application items through the existing quarantine lifecycle.

**Tech Stack:** Swift 6, SwiftUI, Foundation actors/task groups, Swift Package Manager, executable core contract checks.

**Spec:** `docs/superpowers/specs/2026-08-25-inline-batch-application-uninstall-design.md`

## Global Constraints

- macOS 13 minimum.
- No application or uninstall item is selected by default after scanning.
- System, running, shared, user-data, unverifiable, and path-policy-blocked items cannot enter a batch.
- Association roots are enumerated once per application-module scan.
- Analysis budgets must be visible as limited coverage rather than hidden truncation.
- Batch execution still uses `CleanupExecutor`, history receipts, quarantine scheduling, restore, and purge.

---

### Task 1: Batch selection model

**Files:**
- Create: `Sources/CleanerCore/UninstallBatchSelectionState.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`

**Interfaces:**
- Produces: `UninstallBatchSelectionState`, `UninstallBatchSummary`, `selectionState(for:)`, `toggle(plan:)`, and `toggle(item:)`.
- Consumes: `UninstallPlan`, `UninstallItem`, and `SelectionTriState`.

- [ ] Add contracts proving initial selection is empty, app toggles select recommended IDs, child toggles create partial state, protected IDs cannot be selected, and summaries count multiple applications without double-counting paths.
- [ ] Run `Scripts/build-app.sh`; expect failure because `UninstallBatchSelectionState` is missing.
- [ ] Implement the pure selection type. Define selectable IDs as `plan.recommendedSelectionIDs`; sanitize externally supplied IDs against all selectable plan items; deduplicate summary bytes by standardized candidate path.
- [ ] Run `Scripts/build-app.sh`; expect `Core contracts passed`.
- [ ] Commit `feat: model batch application uninstall selection`.

### Task 2: Scan-owned uninstall analyses

**Files:**
- Create: `Sources/CleanerCore/ApplicationUninstallAnalysis.swift`
- Modify: `Sources/CleanerCore/ApplicationScanner.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`

**Interfaces:**
- Produces: `ApplicationUninstallCoverageState`, `ApplicationUninstallAnalysis`, `ApplicationUninstallInventory`, and `ApplicationUninstallAnalyzer.analyze(inventory:context:)`.
- Updates: `ApplicationScanner.associationIndex(for:context:)` and `UninstallPlanner.planUninstall(_:associations:context:maximumSizeEntries:)`.

- [ ] Add contracts with two applications and shared association roots. Assert analyses exist without a UI selection, association roots are requested once, system/running apps are protected, and a small size budget reports limited coverage while retaining safe concrete items.
- [ ] Run `Scripts/build-app.sh`; expect failure because analysis inventory APIs are missing.
- [ ] Implement one-pass association indexing. Enumerate each configured association root once, normalize `.plist`/`.savedState` names, and match exact Bundle ID/app-name boundaries; preserve user-data/shared protection flags.
- [ ] Refactor `UninstallPlanner` to accept preindexed associations and return whether recursive sizing reached its budget. Keep the existing convenience API for focused contracts.
- [ ] Implement bounded analysis with at most four concurrent non-protected applications and 5,000 recursive size entries per app. Produce terminal complete/limited/protected/unavailable analysis for every discovered app.
- [ ] Run `Scripts/build-app.sh`; expect all contracts to pass.
- [ ] Commit `feat: analyze application uninstall scope during scan`.

### Task 3: Shared report propagation

**Files:**
- Modify: `Sources/CleanerCore/SystemScanReport.swift`
- Modify: `Sources/CleanerCore/SystemScanCoordinator.swift`
- Modify: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Updates: `SystemScanModulePayload.applications(ApplicationUninstallInventory)`.
- Produces: `SystemScanReport.applicationUninstallInventory` and `SystemScanReport.uninstallAnalysis(for:)`.

- [ ] Add a coordinator contract asserting every discovered application has a terminal uninstall analysis before the report commits.
- [ ] Run `Scripts/build-app.sh`; expect the report API assertion to fail to compile.
- [ ] Make the applications task discover apps, analyze them, publish progress, and return the combined inventory. Mark the module limited if discovery or any analysis is limited/unavailable.
- [ ] Propagate both installed applications and analyses through report initialization and module replacement.
- [ ] Run `Scripts/build-app.sh`; expect all contracts to pass.
- [ ] Commit `feat: include uninstall analyses in system reports`.

### Task 4: App model batch lifecycle

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`

**Interfaces:**
- Produces app-facing computed values `uninstallAnalyses`, `uninstallBatchSummary`, `uninstallSelectionState(for:)`, `toggleUninstallPlan(_:)`, `toggleUninstall(_:)`, and `executeUninstallBatch()`.
- Removes selected-row plan generation from `inspectUninstall(_:)` and single-plan execution from `executeUninstall()`.

- [ ] Add pure batch-flattening contracts that selected items across two plans become one deduplicated candidate list and protected items remain absent.
- [ ] Run contracts and verify the new batch helper is missing.
- [ ] Install scan-owned analyses in `AppModel`; clear batch selection on generation changes and sanitize it on application refresh.
- [ ] Build one cleanup plan from all selected analysis items, execute it once, append one receipt, register quarantine retention, reload history/schedules, and refresh the application module.
- [ ] Run `Scripts/build-app.sh`; expect all contracts to pass.
- [ ] Commit `feat: execute application uninstall batches`.

### Task 5: Inline expandable application page

**Files:**
- Rewrite: `Sources/CleanerApp/ApplicationsView.swift`
- Modify: `Sources/CleanerApp/ContentView.swift` only if the shared bottom plan bar conflicts with the application batch bar.

**Interfaces:**
- Consumes scan-owned analyses and AppModel batch methods from Tasks 3–4.
- Removes `ApplicationInspector` and `UninstallPlanSheet`.

- [ ] Make the page a full-width `ScrollView`/`LazyVStack` of disclosure rows while retaining search, scopes, refresh, selected-row highlight, and accessibility labels.
- [ ] Render compact row columns for checkbox/protection, app identity, state/coverage, recommended count, and bytes. Expanding a row renders child checkboxes, evidence, size, and protection badges.
- [ ] Add a persistent bottom batch bar with selected application count, item count, bytes, quarantine safety copy, and one `移动所选项目到隔离区` action.
- [ ] Remove the inspector split, “查看推荐卸载计划” button, plan sheet, and their state bindings.
- [ ] Run `Scripts/build-app.sh`; expect the release app to compile and all contracts to pass.
- [ ] Commit `feat: embed batch uninstall plans in application list`.

### Task 6: Verification and documentation

**Files:**
- Create: `docs/verification/2026-08-25-inline-batch-application-uninstall-verification.md`

**Interfaces:**
- Verifies all preceding tasks as one user flow.

- [ ] Run `Scripts/build-app.sh` and record `Core contracts passed`.
- [ ] Run `Scripts/verify-app.sh` and record signature plus cleanup/restore smoke success.
- [ ] Run `git diff --check`.
- [ ] Relaunch the app, run a read-only system scan, confirm summaries appear before row focus, expand at least two application rows, select both, confirm partial/all states and batch totals, then deselect without invoking the destructive action.
- [ ] Record actual evidence and environmental limitations in the verification document.
- [ ] Commit `docs: verify inline batch application uninstall`.
