# Interaction and Lifecycle Coherence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Disk Space selection consistent, Agent Environment platform-fair and structured, and quarantine deletion automatically scheduled with a 24-hour default.

**Architecture:** Materialize every safe concrete disk file as a manual-review candidate, centralize row gestures, traverse Agent providers round-robin with explicit coverage, and add an atomic quarantine schedule store plus an in-app/catch-up scheduler. All destructive work continues through `CleanupExecutor.purge` and its receipt ownership checks.

**Tech Stack:** Swift 6, SwiftUI, Foundation actors/tasks, Swift Package Manager, executable core contract checks.

**Spec:** `docs/superpowers/specs/2026-08-25-interaction-and-lifecycle-coherence-design.md`

## Global Constraints

- macOS 13 minimum.
- Default automatic deletion policy is 24 hours.
- Automatic deletion is app-runtime plus next-launch catch-up; do not silently install a LaunchAgent.
- Directories are navigation only and never cleanup candidates.
- Every destructive operation must match quarantine root, plan ID, and candidate ID.
- Follow RED -> GREEN for each behavior change.

---

### Task 1: Disk file candidate parity

**Files:**
- Modify: `Sources/CleanerCore/DiskUsageScanner.swift`
- Modify: `Sources/CleanerCore/GeneralScanners.swift`
- Modify: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Produces: `DiskUsageTree.concreteFiles` and `LargeFileScanner.candidates(from:context:)` for every concrete file.
- Preserves: `DiskUsageTree.largeFiles` as the `>= minimumFileBytes` metric.

- [ ] Add a contract with one sub-threshold concrete file and assert it receives a `review` candidate while directories do not.
- [ ] Run `Scripts/build-app.sh` and confirm the contract fails because only `largeFiles` become candidates.
- [ ] Add recursive `concreteFiles` collection and create candidates for every concrete file with explicit-selection evidence.
- [ ] Run `Scripts/build-app.sh`; confirm all core contracts pass.
- [ ] Commit `feat: make disk file selection consistent`.

### Task 2: Stable directory gestures

**Files:**
- Create: `Sources/CleanerCore/DirectoryRowInteraction.swift`
- Modify: `Sources/CleanerApp/DiskUsageOutlineView.swift`
- Modify: `Sources/CoreContractChecks/ReviewInteractionContract.swift`

**Interfaces:**
- Produces: `DirectoryRowInteraction.action(for:clickCount:kind:hasChildren:)` returning `select` or `selectAndToggleExpansion`.

- [ ] Add contracts: one click selects; two clicks on a non-empty directory select and toggle; two clicks on a file only select; empty directories do not toggle.
- [ ] Run `Scripts/build-app.sh` and confirm the interaction type is missing.
- [ ] Implement the pure interaction policy and one exclusive row gesture so single and double click do not compete.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `fix: make directory double click deterministic`.

### Task 3: Agent provider fairness and coverage

**Files:**
- Modify: `Sources/CleanerCore/AgentScanners.swift`
- Modify: `Sources/CleanerCore/SystemScanReport.swift`
- Modify: `Sources/CleanerCore/SystemScanCoordinator.swift`
- Modify: `Sources/CoreContractChecks/AgentScannerContract.swift`

**Interfaces:**
- Produces: `AgentProviderCoverage`, `AgentAssetInventory.providerCoverage`, round-robin `scanAssetInventory(context:)`.
- Updates: `SystemScanModulePayload.agentEnvironment(AgentAssetInventory)`.

- [ ] Add a wide Codex fixture plus smaller Claude and Trae fixtures under a constrained budget; assert every detected provider receives assets and limited coverage is attributed correctly.
- [ ] Run `Scripts/build-app.sh`; confirm Codex consumes the budget and the contract fails.
- [ ] Discover all roots first, traverse active providers round-robin, and produce coverage for every `AgentProvider.allCases` value.
- [ ] Propagate the inventory through the shared system report and module refresh path.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `feat: scan agent providers fairly`.

### Task 4: Platform-first Agent UI

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CleanerApp/AgentEnvironmentView.swift`
- Modify: `Sources/CleanerCore/AgentAssetGrouping.swift`
- Modify: `Sources/CoreContractChecks/AgentScannerContract.swift`

**Interfaces:**
- Produces: provider summaries for all supported providers and platform selection independent of filter disappearance.

- [ ] Add grouping contracts that include not-detected providers and preserve provider ordering/names.
- [ ] Run `Scripts/build-app.sh` and confirm the new summaries are absent.
- [ ] Add platform overview cards and selected-platform detail hierarchy; rename the two view modes.
- [ ] Show complete, limited, unavailable, and not-detected coverage in cards and header.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `feat: restructure agent environment by platform`.

### Task 5: Quarantine retention model and store

**Files:**
- Create: `Sources/CleanerCore/QuarantineSchedule.swift`
- Create: `Sources/CleanerCore/QuarantineScheduleStore.swift`
- Modify: `Sources/CoreContractChecks/StoreContract.swift`

**Interfaces:**
- Produces: `QuarantineRetentionPolicy`, `QuarantineSchedule`, `QuarantineScheduleStore.upsert/remove/dueSchedules/all`.

- [ ] Add contracts for 24-hour default, 2/3/7/30-day deadlines, permanent retention, atomic replacement, and due ordering.
- [ ] Run `Scripts/build-app.sh` and confirm schedule types are missing.
- [ ] Implement Codable policy/deadline calculation and an atomic actor store keyed by receipt ID.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `feat: persist quarantine retention schedules`.

### Task 6: Automatic purge coordinator

**Files:**
- Create: `Sources/CleanerCore/QuarantineMaintenanceCoordinator.swift`
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CoreContractChecks/PlanningExecutionContract.swift`

**Interfaces:**
- Produces: `QuarantineMaintenanceCoordinator.processDue(now:)` and `schedule(receipt:policy:)`.
- Consumes: `HistoryStore`, `QuarantineScheduleStore`, `CleanupExecutor`.

- [ ] Add contracts that due quarantined receipts purge, future/permanent schedules remain, restore-resolved receipts cancel schedules, failures retain schedules, and ownership validation still rejects forged paths.
- [ ] Run `Scripts/build-app.sh` and confirm coordinator is missing.
- [ ] Implement one-action-at-a-time processing with immediate history replacement and schedule removal only after all quarantined items resolve.
- [ ] Schedule new receipts after execution, migrate unresolved legacy receipts on bootstrap, process due schedules on bootstrap, and run a bounded periodic task while the app is alive.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `feat: automate due quarantine deletion`.

### Task 7: Retention settings and countdown UI

**Files:**
- Modify: `Sources/CleanerApp/PermissionsView.swift`
- Modify: `Sources/CleanerApp/HistoryView.swift`
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CoreContractChecks/ReviewInteractionContract.swift`

**Interfaces:**
- Produces: persisted global default, per-receipt rescheduling, countdown labels, overdue/failed states.

- [ ] Add presentation contracts for every retention label and countdown boundary.
- [ ] Run `Scripts/build-app.sh` and confirm presentation APIs are absent.
- [ ] Add the default retention picker in Settings, defaulting to 24 hours.
- [ ] Add per-receipt policy picker, scheduled date/countdown, permanent retention, and explicit manual-delete override.
- [ ] Ensure restore removes the schedule and manual purge resolves it.
- [ ] Run `Scripts/build-app.sh`; confirm all contracts pass.
- [ ] Commit `feat: add quarantine retention controls`.

### Task 8: Full verification

**Files:**
- Create: `docs/verification/2026-08-25-coherence-and-retention-verification.md`

- [ ] Run `Scripts/build-app.sh` and confirm `Core contracts passed`.
- [ ] Run `Scripts/verify-app.sh` and confirm signature plus cleanup/restore smoke flow pass.
- [ ] Run `git diff --check`.
- [ ] Relaunch the app and verify disk checkbox/button parity, directory double-click expansion/collapse, Agent platform cards, and retention controls without executing destructive actions.
- [ ] Record evidence and remaining environmental limitations in the verification document.
- [ ] Commit `docs: verify coherent cleanup interactions`.
