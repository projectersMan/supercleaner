# Guided Cleanup Modes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Historical note:** This document preserves the original implementation sequence. The current product no longer has a separate zero-write preview stage; the safety boundary is an immutable plan plus mandatory revalidation immediately before real execution.

**Goal:** Make routine cleanup recommendation-led and one-confirmation, while preserving a full custom workbench and adding native application selection.

**Architecture:** A pure CleanerCore recommendation policy separates engine advice from safety risk. AppModel applies deterministic mode selections, summary-first SwiftUI renders Smart/Deep modes, and Application Management uses native focus plus recommended uninstall defaults.

**Tech Stack:** Swift 6, SwiftUI, CleanerCore contract executable, XCTest sources

**Spec:** `docs/superpowers/specs/2026-08-24-guided-cleanup-modes-design.md`

## Global Constraints

- No Mole source, shell, copy, icons, or structure may be reused.
- Protected candidates remain unselectable in every mode.
- Real execution must perform mandatory path, identity, activity, rule-version, and expiry revalidation before any mutation.
- Execution remains recoverable and revalidates identity, activity, rule version, and expiry.
- Smart and Deep mode changes replace selection; visual filtering does not.
- No new third-party dependencies.

---

### Task 1: Recommendation Policy and Mode Selection

**Files:**
- Create: `Sources/CleanerCore/CleanupRecommendationPolicy.swift`
- Create: `Sources/CoreContractChecks/CleanupRecommendationContract.swift`
- Create: `Tests/CleanerCoreTests/CleanupRecommendationPolicyTests.swift`
- Modify: `Sources/CoreContractChecks/main.swift`

**Interfaces:**
- Produces: `CleanupDisposition`, `CleanupMode`, `CleanupRecommendationPolicy.disposition(for:)`, and `selectedIDs(for:mode:currentSelection:)`.
- Consumes: `CleanupCandidate`, `RiskLevel`, and `CleanupCategory`.

- [ ] **Step 1: Write failing contract and XCTest cases**

Create fixtures proving: safe → recommended; blocked → protected; inactive review cache/model/package/developer/installer/log/temp → deepClean; active or context-bearing review → retain; Smart selects only recommended; Deep adds deepClean; Custom preserves explicit selectable IDs and removes blocked IDs.

- [ ] **Step 2: Run RED**

Run `swift build -c release --product CoreContractChecks && .build/release/CoreContractChecks`.
Expected: compile failure because `CleanupRecommendationPolicy` does not exist.

- [ ] **Step 3: Implement minimal pure policy**

Implement the four dispositions and three modes as `Codable, Hashable, Sendable, CaseIterable`. Use a category set for deep-clean eligibility, reject active items, and filter Custom selection through `risk.isSelectable`.

- [ ] **Step 4: Run GREEN and mutation check**

Run the contract command; then temporarily remove `.agentModelCache` from deep eligibility and verify the contract fails. Restore it and rerun green.

- [ ] **Step 5: Commit**

Commit as `feat: add cleanup recommendation policy`.

---

### Task 2: Cleanup Mode Lifecycle

**Files:**
- Modify: `Sources/CleanerApp/ReviewWorkspaceState.swift`
- Modify: `Sources/CleanerApp/AppModel.swift`
- Create: `Sources/CoreContractChecks/CleanupModeContract.swift`
- Modify: `Sources/CoreContractChecks/main.swift`

**Interfaces:**
- Produces: `cleanupMode`, `setCleanupMode(_:)`, recommendation partitions, grouped summaries, and plain summary counts.
- Consumes: Task 1 policy and existing plan invalidation.

- [ ] **Step 1: Write failing lifecycle contract**

Prove mode transitions yield literal selected-ID sets; switching modes invalidates the pending execution plan through an App-independent `CleanupModeSelectionState` value type.

- [ ] **Step 2: Run RED**

Run CoreContractChecks. Expected: compile failure because `CleanupModeSelectionState` is missing.

- [ ] **Step 3: Implement mode state and AppModel integration**

Add a value type that applies policy selection. AppModel defaults to Smart, applies Smart after scan, applies new selection in `setCleanupMode`, invalidates the pending execution plan when selection changes, and exposes recommended/deep/retained/protected arrays plus byte totals.

- [ ] **Step 4: Run GREEN and release build**

Run CoreContractChecks and `./Scripts/build-app.sh`.

- [ ] **Step 5: Commit**

Commit as `feat: manage guided cleanup modes`.

---

### Task 3: Summary-First Cleanup UI

**Files:**
- Create: `Sources/CleanerApp/GuidedCleanupView.swift`
- Modify: `Sources/CleanerApp/CleanupReviewView.swift`
- Modify: `Sources/CleanerApp/Components.swift`
- Modify: `Sources/CleanerApp/ReviewWorkspaceState.swift`

**Interfaces:**
- Produces: segmented mode picker, category summary rows, retained/protected disclosures, and “查看项目” transition.
- Consumes: Task 2 AppModel partitions and existing ReviewWorkspaceView for Custom mode.

- [ ] **Step 1: Add view-facing copy contract first**

Add a CoreContractChecks contract for `CleanupDisposition.displayTitle` exposed from an App-independent presentation type: expected titles are `推荐清理 / 深度清理 / 默认保留 / 始终保护`. Run RED.

- [ ] **Step 2: Implement recommendation presentation**

Replace “需要确认” risk labels and filter title with recommendation-aware labels. Candidate rows and inspector state state whether an item is recommended, retained, or protected.

- [ ] **Step 3: Implement summary-first modes**

Smart and Deep render category groups and compact retained/protected explanations. Custom alone renders filters, list, checkboxes, and inspector. “查看项目” switches to Custom without changing current IDs.

- [ ] **Step 4: Build**

Run `./Scripts/build-app.sh`. Expected: all release products pass.

- [ ] **Step 5: Commit**

Commit as `feat: simplify guided cleanup interface`.

---

### Task 4: Native Application Selection and Recommended Uninstall

**Files:**
- Modify: `Sources/CleanerCore/ApplicationScanner.swift`
- Modify: `Sources/CleanerApp/AppModel.swift`
- Rewrite: `Sources/CleanerApp/ApplicationsView.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`
- Modify: `Tests/CleanerCoreTests/ApplicationScannerTests.swift`

**Interfaces:**
- Produces: `UninstallPlan.recommendedSelectionIDs`, AppModel selected application focus, a split list/inspector, and a summary-first uninstall sheet.
- Consumes: exact Bundle-ID ownership and current blocked user/shared-data rules.

- [ ] **Step 1: Write failing uninstall-default tests**

Prove the application bundle and exact cache/preference/saved-state/launch-agent items are recommended; running/system app bundles and user/shared items are excluded. Run RED because `recommendedSelectionIDs` is missing.

- [ ] **Step 2: Implement uninstall recommendations**

Add the derived selection set to `UninstallPlan`; initialize `uninstallSelectedIDs` from it when inspection completes.

- [ ] **Step 3: Implement native selection and inspector**

Bind application `List(selection:)` to `selectedApplicationID`. Use a split view with selected highlight, application facts, protection explanation, and one “检查卸载建议” button. Reconcile focus after application reload.

- [ ] **Step 4: Simplify uninstall sheet**

Show included/retained/protected summary and recommendation labels. Checkboxes mean plan membership; remove “逐项确认” and “需要确认” copy. Keep one final quarantine action and all blocked-state enforcement.

- [ ] **Step 5: Run contracts, build, and commit**

Run CoreContractChecks and `./Scripts/build-app.sh`. Commit as `feat: simplify application uninstall review`.

---

### Task 5: Acceptance and Documentation

**Files:**
- Modify: `docs/verification/2026-08-24-macos-cleaner-verification.md`

**Interfaces:**
- Verifies all earlier tasks; produces no runtime interface.

- [ ] **Step 1: Run command-line gates**

Run `./Scripts/build-app.sh && ./Scripts/verify-app.sh && git diff main...HEAD --check`.

- [ ] **Step 2: Run read-only GUI acceptance**

Verify Smart summary, Deep trade-off, Custom workbench, application highlight/inspector, default uninstall suggestions, AX semantics, final confirmation, and mode-change plan invalidation. Do not execute cleanup or uninstall.

- [ ] **Step 3: Record evidence**

Update verification documentation without committing private scanned paths.

- [ ] **Step 4: Final verification and commit**

Rerun all command-line gates, require a clean worktree, and commit as `docs: verify guided cleanup modes`.
