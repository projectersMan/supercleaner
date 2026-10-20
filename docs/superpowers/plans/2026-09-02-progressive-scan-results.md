# Progressive Scan Results Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish each completed scan module immediately and make its overview progress row navigate to the corresponding populated result page while the remaining modules continue scanning.

**Architecture:** `SystemScanCoordinator` emits a typed `SystemScanModuleResult` after each worker finishes. `AppModel` merges that payload into a current-generation progressive report, preserving untouched results from the prior report and rejecting stale generations. `DashboardView` asks the navigation policy and model whether a result really exists before presenting an entire progress row as a button.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, existing CoreContractChecks and macOS app verification scripts.

**Spec:** `docs/superpowers/specs/2026-09-02-progressive-scan-results-design.md`

## Global Constraints

- Only `.completed` and `.limited` modules are navigable.
- A module must have an installed payload for the current scan before navigation is enabled.
- Late results from an older `generationID` must not overwrite the active scan.
- Progressive publication is memory-only and must never clean, quarantine, uninstall, or upload data.
- Existing result pages and sidebar destinations remain the single source of destination UI.

---

### Task 1: Result navigation policy

**Files:**
- Modify: `Sources/CleanerCore/AppNavigationPolicy.swift`
- Test: `Sources/CoreContractChecks/AppNavigationContract.swift`

**Interfaces:**
- Consumes: `ScanModuleID`, `ScanModuleState`, and `AppDestination`.
- Produces: `AppNavigationPolicy.scanResultDestination(for:state:) -> AppDestination?`.

- [ ] **Step 1: Write the failing contract**

Add assertions that general, applications, large files, and Agent results map to their existing destinations for `.completed` and `.limited`, while `.waiting`, `.scanning`, `.failed`, and `.cancelled` return `nil`.

- [ ] **Step 2: Verify RED**

Run `swift run CoreContractChecks` and confirm compilation fails because `scanResultDestination(for:state:)` does not exist.

- [ ] **Step 3: Implement the policy**

Add one exhaustive switch that first accepts only `.completed`/`.limited`, then maps `.general` to `.cleanupCenter`, `.applications` to `.applications`, `.largeFiles` to `.largeFiles`, and `.agentEnvironment` to `.agentEnvironment`.

- [ ] **Step 4: Verify GREEN**

Run `swift run CoreContractChecks` and confirm all core contracts pass.

- [ ] **Step 5: Commit**

Commit the policy and contract as `feat(navigation): map completed scan results`.

### Task 2: Typed progressive module publication

**Files:**
- Modify: `Sources/CleanerCore/SystemScanCoordinator.swift`
- Modify: `Sources/CleanerCore/SystemScanReport.swift`
- Test: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Consumes: existing `SystemScanModulePayload`, `SystemScanModuleStatus`, and coordinator outcomes.
- Produces: `SystemScanModuleResult` and `SystemScanReport.replacing(moduleResult:)`.

- [ ] **Step 1: Write failing merge contracts**

Construct a report with prior results, replace one module with a result carrying a fixed generation ID, and assert that the target payload/status changes, untouched payloads remain, and the report generation remains fixed.

- [ ] **Step 2: Verify RED**

Run `swift run CoreContractChecks` and confirm failure because `SystemScanModuleResult` and `replacing(moduleResult:)` are missing.

- [ ] **Step 3: Implement typed results and merge**

Define a sendable result containing `generationID`, `status`, and `payload`. Add a `moduleResult` callback to `scan`, emit it from the task-group outcome loop, and add a report replacement method that preserves existing payloads while using the supplied generation and status.

- [ ] **Step 4: Verify GREEN**

Run `swift run CoreContractChecks` and confirm all contracts pass.

- [ ] **Step 5: Commit**

Commit as `feat(scan): publish completed module results`.

### Task 3: Current-generation installation and clickable rows

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CleanerApp/DashboardView.swift`
- Test: `Sources/CoreContractChecks/AppNavigationContract.swift`

**Interfaces:**
- Consumes: `SystemScanModuleResult`, `AppNavigationPolicy.scanResultDestination(for:state:)`.
- Produces: `AppModel.canOpenScanResult(_:)`, `AppModel.openScanResult(_:)`, progressive result installation, and row button semantics.

- [ ] **Step 1: Add the model-facing navigation contract**

Extend the policy contract to prove nonterminal states never expose destinations; this is the pure boundary used by the app model.

- [ ] **Step 2: Implement generation guarding and progressive install**

Record the active generation from progress events, ignore events/results not belonging to it, seed the progressive report from the previous report, merge only the finished module, and leave the final full-report installation unchanged.

- [ ] **Step 3: Implement row navigation**

Render the main module row as a plain button only when the current report contains a navigable result. Add a trailing chevron and hover affordance; keep the limitation disclosure as its own sibling button.

- [ ] **Step 4: Build and run contracts**

Run `swift run CoreContractChecks && swift build --product CleanerApp` and confirm success.

- [ ] **Step 5: Commit**

Commit as `feat(dashboard): open progressive scan results`.

### Task 4: Release and interaction verification

**Files:**
- Modify only if verification identifies a defect.

**Interfaces:**
- Consumes: the completed implementation.
- Produces: a verified `build/SuperCleaner.app`.

- [ ] **Step 1: Run full release verification**

Run `./scripts/build-app.sh && ./scripts/verify-app.sh && git diff --check` and require zero failures.

- [ ] **Step 2: Exercise the live flow**

Start a full scan, wait for one module to finish while another remains scanning, click the completed row, verify the populated destination appears, return to overview, verify a scanning row is not clickable, and verify `查看原因` expands without navigation.

- [ ] **Step 3: Inspect visual states**

Check default, hover, enabled, disabled, expanded-limitations, and post-navigation states for clipping, duplicate controls, and unclear feedback.

- [ ] **Step 4: Commit verification fixes if needed**

If no source fix is needed, do not create an empty commit. Otherwise commit focused fixes as `fix(dashboard): refine progressive result navigation`.
