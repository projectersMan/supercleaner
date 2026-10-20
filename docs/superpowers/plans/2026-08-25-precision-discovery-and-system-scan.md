# Precision Discovery and System Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one read-only full-system scan launched from Overview, feed every result page from the same versioned report, and add precise application, large-file, Agent, and cleanup-plan review interactions.

**Architecture:** `CleanerCore` owns versioned scan-report primitives and four bounded discovery modules. `CleanerApp.AppModel` orchestrates a report generation, preserves the last completed report during cancellation, and invalidates selections and pending execution plans when the generation changes. SwiftUI pages consume only that shared report and progressively disclose details through native lists, outlines, selection, and inspectors.

**Tech Stack:** Swift 6, Swift Concurrency, SwiftUI for macOS 13+, XCTest, Swift Package Manager, existing `FileSystemAccess`, `PathPolicy`, quarantine executor, and `Scripts/build-app.sh`.

**Spec:** `docs/superpowers/specs/2026-08-25-precision-discovery-and-review-design.md`

## Global Constraints

- Scanning, tree expansion, application enumeration, and Agent classification perform zero writes.
- Symbolic links are never traversed during recursive discovery.
- The first full-system scan is launched only from Overview with the label `开始完整扫描`.
- Cleanup Center, Applications, Large Files, and Agent Environment consume one versioned report generation.
- Cancelling a scan preserves the last completed report and never installs a partial generation.
- Every scanner has explicit depth and entry budgets and preserves successful partial results.
- Large-file directories are navigation nodes, never selectable cleanup candidates.
- Agent credentials, Skills, MCP definitions, prompts, knowledge, configuration, source code, active sessions, and worktree roots remain protected.
- Any report-generation change invalidates selected overrides and executable plans.
- macOS deployment floor remains 13.0 and no third-party dependency is added.

---

### Task 1: Shared Scan Lifecycle Primitives

**Files:**
- Create: `Sources/CleanerCore/SystemScanPrimitives.swift`
- Modify: `Sources/CleanerCore/Scanner.swift`
- Create: `Tests/CleanerCoreTests/SystemScanPrimitivesTests.swift`
- Modify: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Produces: `ScanModuleID`, `ScanModuleState`, `ScanModuleStatus`, `ScanGenerationMetadata`, and `CoverageSummary`.
- Consumes: existing `ScanFailure`; payload-independent primitives allow Tasks 2–4 to compile before the aggregate report is introduced in Task 5.

- [ ] **Step 1: Write failing lifecycle primitive tests**

```swift
func testOnlyTerminalModuleStatesAreTerminal() {
    XCTAssertTrue(ScanModuleState.completed.isTerminal)
    XCTAssertTrue(ScanModuleState.limited.isTerminal)
    XCTAssertTrue(ScanModuleState.failed.isTerminal)
    XCTAssertTrue(ScanModuleState.cancelled.isTerminal)
    XCTAssertFalse(ScanModuleState.waiting.isTerminal)
    XCTAssertFalse(ScanModuleState.scanning.isTerminal)
}

func testCoverageCombinesUnavailableRootsWithoutDuplicates() {
    let root = URL(fileURLWithPath: "/Users/tester/Downloads")
    let coverage = CoverageSummary(
        scannedRoots: [],
        unavailableRoots: [root, root],
        budgetLimitedModules: []
    )
    XCTAssertEqual(coverage.unavailableRoots, [root])
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run: `swift test --filter SystemScanPrimitivesTests`

Expected: compilation fails because the module and coverage primitives do not exist.

- [ ] **Step 3: Implement immutable generation and module-state types**

```swift
public enum ScanModuleID: String, Codable, CaseIterable, Sendable {
    case general, applications, largeFiles, agentEnvironment
}

public enum ScanModuleState: String, Codable, Sendable {
    case waiting, scanning, completed, limited, failed, cancelled
}

public struct ScanModuleStatus: Codable, Hashable, Sendable {
    public let module: ScanModuleID
    public let state: ScanModuleState
    public let startedAt: Date?
    public let completedAt: Date?
    public let message: String?
}

public struct CoverageSummary: Codable, Hashable, Sendable {
    public let scannedRoots: [URL]
    public let unavailableRoots: [URL]
    public let budgetLimitedModules: Set<ScanModuleID>
}
```

`CoverageSummary.init` standardizes and deduplicates roots, and `ScanGenerationMetadata` contains `generationID`, `startedAt`, `completedAt`, and `rulesetVersion`.

- [ ] **Step 4: Keep `ScanCoordinator` as the general-candidate worker**

Rename no existing public scanner protocol. Preserve `ScanReport` as the internal result for the general module so current scanner contracts remain source compatible while `SystemScanReport` becomes the app-facing aggregate.

- [ ] **Step 5: Run focused and existing scanner tests**

Run: `swift test --filter SystemScanPrimitivesTests && swift test --filter ScannerTests`

Expected: PASS, including failure containment, terminal-state semantics, and coverage normalization.

- [ ] **Step 6: Add contract assertions and commit**

Add deterministic assertions to `ScannerContract` for terminal-state semantics and standardized coverage roots.

```bash
git add Sources/CleanerCore/SystemScanPrimitives.swift Sources/CleanerCore/Scanner.swift Tests/CleanerCoreTests/SystemScanPrimitivesTests.swift Sources/CoreContractChecks/ScannerContract.swift
git commit -m "feat: add system scan lifecycle primitives"
```

### Task 2: Bounded Recursive Application Inventory

**Files:**
- Modify: `Sources/CleanerCore/ApplicationScanner.swift`
- Modify: `Tests/CleanerCoreTests/ApplicationScannerTests.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`

**Interfaces:**
- Consumes: `CoverageSummary` from Task 1 and `FileSystemAccess`.
- Produces: `ApplicationInventory` and `ApplicationScanner.installedApplications(context:runningBundleIdentifiers:maximumDepth:maximumEntries:) async -> ApplicationInventory`.

- [ ] **Step 1: Write failing recursive-discovery tests**

```swift
func testRecursivelyFindsNestedAppsAndTreatsBundlesAsAtomic() async {
    let result = await fixture.scanner.installedApplications(
        context: fixture.context,
        maximumDepth: 4,
        maximumEntries: 100
    )
    XCTAssertEqual(result.applications.map(\.name), ["Nested", "Top Level"])
    XCTAssertFalse(fixture.fileSystem.requestedChildren.contains("/Applications/Nested.app"))
}

func testDeduplicatesStandardizedPathsAndKeepsPartialCoverage() async {
    let result = await fixture.scanner.installedApplications(context: fixture.context)
    XCTAssertEqual(Set(result.applications.map { $0.bundleURL.standardizedFileURL }).count, result.applications.count)
    XCTAssertTrue(result.coverage.unavailableRoots.contains(fixture.unreadableRoot))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ApplicationScannerTests`

Expected: compilation fails because the method returns an array and lacks recursion controls.

- [ ] **Step 3: Implement `ApplicationInventory` and bounded traversal**

```swift
public struct ApplicationInventory: Codable, Hashable, Sendable {
    public let applications: [InstalledApplication]
    public let coverage: CoverageSummary
    public let scannedAt: Date
}
```

Traverse `/Applications`, `~/Applications`, `/System/Applications`, and `/System/Applications/Utilities` with a `(url, depth)` queue. Insert standardized paths into `seenPaths`; when `pathExtension == "app"`, decode the bundle and do not enqueue children. Stop at depth 4 or the entry budget, and record unreadable roots without discarding successful results.

- [ ] **Step 4: Update callers and association fixtures**

Update tests and contract checks to access `.applications`. Do not alter uninstall association boundary matching or protection behavior.

- [ ] **Step 5: Run application and uninstall coverage**

Run: `swift test --filter ApplicationScannerTests && swift run CoreContractChecks`

Expected: PASS; nested apps are found, bundle contents are not traversed, prefix collisions remain excluded, and protected user data stays blocked.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/ApplicationScanner.swift Tests/CleanerCoreTests/ApplicationScannerTests.swift Sources/CoreContractChecks/ApplicationContract.swift
git commit -m "feat: discover applications recursively"
```

### Task 3: Concrete Large-File Tree

**Files:**
- Create: `Sources/CleanerCore/DiskUsageScanner.swift`
- Modify: `Sources/CleanerCore/GeneralScanners.swift`
- Modify: `Tests/CleanerCoreTests/ScannerTests.swift`
- Create: `Tests/CleanerCoreTests/DiskUsageScannerTests.swift`
- Modify: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Produces: `DiskUsageNode`, `DiskUsageChildren`, `DiskUsageTree`, and `DiskUsageScanner.scan(context:) async -> DiskUsageTree`.
- Consumes: `ScanContext`, `FileIdentity`, `CoverageSummary`, and a 100 MB default file threshold.

- [ ] **Step 1: Write failing hierarchy and safety tests**

```swift
func testTreeAggregatesDirectoriesButSelectsOnlyConcreteFiles() async throws {
    let tree = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: fixture.context)
    let project = tree.node(at: fixture.projectURL)!
    XCTAssertEqual(project.recursiveBytes, 600)
    XCTAssertEqual(tree.largeFiles.map(\.url), [fixture.largeFileURL])
    XCTAssertTrue(tree.largeFiles.allSatisfy { $0.kind == .file })
}

func testSymbolicLinksAreNotTraversed() async throws {
    _ = try await DiskUsageScanner(minimumFileBytes: 100).scan(context: fixture.context)
    XCTAssertFalse(fixture.fileSystem.requestedChildren.contains(fixture.symlinkURL.path))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter DiskUsageScannerTests`

Expected: compilation fails because disk-tree types do not exist.

- [ ] **Step 3: Implement value-tree models**

```swift
public enum DiskUsageChildren: Codable, Hashable, Sendable {
    case unloaded
    case loaded([DiskUsageNode])
    case unavailable(String)
}

public struct DiskUsageNode: Identifiable, Codable, Hashable, Sendable {
    public var id: URL { url.standardizedFileURL }
    public let url: URL
    public let kind: FileIdentity.Kind
    public let ownBytes: UInt64
    public let recursiveBytes: UInt64
    public let childCount: Int
    public let modifiedAt: Date
    public let isReadable: Bool
    public let children: DiskUsageChildren
}
```

Scan Downloads, Desktop, Documents, and Movies. Traverse directories with depth and entry budgets, sort loaded children by recursive bytes, retain directories as navigation, and collect only files at or above 100 MB into `largeFiles`.

- [ ] **Step 4: Remove directory candidates from `LargeFileScanner`**

Keep `LargeFileScanner` as a compatibility adapter that converts `DiskUsageTree.largeFiles` into review-risk `CleanupCandidate` values. It must never emit a directory candidate.

- [ ] **Step 5: Run focused and legacy contracts**

Run: `swift test --filter DiskUsageScannerTests && swift test --filter ScannerTests && swift run CoreContractChecks`

Expected: PASS; directory byte aggregation remains correct and all large-file cleanup candidates are concrete files.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/DiskUsageScanner.swift Sources/CleanerCore/GeneralScanners.swift Tests/CleanerCoreTests/ScannerTests.swift Tests/CleanerCoreTests/DiskUsageScannerTests.swift Sources/CoreContractChecks/ScannerContract.swift
git commit -m "feat: add concrete large-file hierarchy"
```

### Task 4: Structured Agent Assets and Cleanup Units

**Files:**
- Modify: `Sources/CleanerCore/AgentScanners.swift`
- Modify: `Sources/CleanerCore/AgentEnvironmentSummary.swift`
- Modify: `Tests/CleanerCoreTests/AgentScannerTests.swift`
- Modify: `Sources/CoreContractChecks/AgentScannerContract.swift`

**Interfaces:**
- Produces: `AgentProvider`, `AgentScope`, `AgentResourceKind`, `AgentActivity`, `AgentCleanupEligibility`, `AgentAssetRecord`, `TraeProviderAdapter`, and `AgentWorkspaceScanner.scanAssets(context:) async throws -> [AgentAssetRecord]`.
- Consumes: existing provider adapter discovery, exact path components, `CleanupCandidate`, and `PathPolicy`.

- [ ] **Step 1: Write failing provider-ownership and classification tests**

```swift
func testSharedAgentsRootIsOwnedOnceBySharedProvider() async throws {
    let assets = try await fixture.scanner.scanAssets(context: fixture.context)
    let shared = assets.filter { $0.cleanupUnitURL.path.hasPrefix(fixture.sharedRoot.path) }
    XCTAssertTrue(shared.allSatisfy { $0.provider == .shared })
    XCTAssertEqual(Set(shared.map(\.cleanupUnitURL)).count, shared.count)
}

func testFilenameContainingModelIsNotModelCache() async throws {
    let assets = try await fixture.scanner.scanAssets(context: fixture.context)
    XCTAssertNotEqual(assets.first { $0.candidate.displayName == "model-notes.md" }?.resourceKind, .modelCache)
}

func testProtectedKindsAreNeverEligible() async throws {
    let assets = try await fixture.scanner.scanAssets(context: fixture.context)
    let protectedKinds: Set<AgentResourceKind> = [.skill, .mcpDefinition, .credential, .configuration, .promptKnowledge, .sourceCode, .gitWorktree]
    XCTAssertTrue(assets.filter { protectedKinds.contains($0.resourceKind) }.allSatisfy { $0.cleanupEligibility == .protected })
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter AgentScannerTests`

Expected: compilation fails because structured records and Trae/shared ownership do not exist.

- [ ] **Step 3: Define structured dimensions**

```swift
public enum AgentProvider: String, Codable, CaseIterable, Sendable { case codex, claude, cursor, trae, genericMCP, git, shared }
public enum AgentScope: String, Codable, CaseIterable, Sendable { case global, project, shared }
public enum AgentActivity: String, Codable, Sendable { case active, recent, completed, unknown }
public enum AgentCleanupEligibility: String, Codable, Sendable { case recommended, deep, retained, protected }

public struct AgentAssetRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID { candidate.id }
    public let candidate: CleanupCandidate
    public let provider: AgentProvider
    public let scope: AgentScope
    public let resourceKind: AgentResourceKind
    public let activity: AgentActivity
    public let cleanupEligibility: AgentCleanupEligibility
    public let cleanupUnitURL: URL
}
```

- [ ] **Step 4: Make provider roots non-overlapping**

Codex owns only `.codex`; shared owns `.agents`; Claude owns `.claude`; Cursor owns `.cursor` and Cursor support roots; Trae owns `.trae` and Trae support roots; generic MCP owns `.config/mcp`; Git recognizes worktree metadata. Deduplicate standardized paths before classification.

- [ ] **Step 5: Replace substring classification with path-role classification**

Use exact components such as `models`, `sessions`, `skills`, `sandboxes`, `workspaces`, and known cache directories. Recommended eligibility requires reproducibility, inactive state, valid identity, non-symlink kind, and completion/age evidence. Aggregate internal descendants into meaningful cleanup units instead of returning every internal file.

- [ ] **Step 6: Preserve the legacy candidate surface temporarily**

Implement `scan(context:)` by mapping unique selectable cleanup units from `scanAssets(context:)`. This keeps existing recommendation and execution paths operational until the UI consumes structured records directly.

- [ ] **Step 7: Run Agent safety coverage and commit**

Run: `swift test --filter AgentScannerTests && swift run CoreContractChecks`

Expected: PASS; Skills, MCP, credentials, knowledge, source, active assets, and worktrees are protected; model/package caches are deep; only inactive completed reproducible caches are recommended.

```bash
git add Sources/CleanerCore/AgentScanners.swift Sources/CleanerCore/AgentEnvironmentSummary.swift Tests/CleanerCoreTests/AgentScannerTests.swift Sources/CoreContractChecks/AgentScannerContract.swift
git commit -m "feat: structure agent environment assets"
```

### Task 5: Full-System Scan Orchestrator

**Files:**
- Create: `Sources/CleanerCore/SystemScanReport.swift`
- Create: `Sources/CleanerCore/SystemScanCoordinator.swift`
- Create: `Tests/CleanerCoreTests/SystemScanCoordinatorTests.swift`
- Modify: `Sources/CoreContractChecks/ScannerContract.swift`

**Interfaces:**
- Consumes: `ScanCoordinator`, `ApplicationScanner`, `DiskUsageScanner`, `AgentWorkspaceScanner`, and lifecycle primitives from Task 1.
- Produces: `SystemScanReport`, `SystemScanReport.replacing(module:payload:completedAt:)`, `SystemScanProgressEvent`, and `SystemScanCoordinator.scan(context:runningBundleIdentifiers:progress:) async -> SystemScanReport?`.

- [ ] **Step 1: Write failing orchestration tests**

```swift
func testAllModulesShareOneGenerationAndEmitProgress() async {
    var events: [SystemScanProgressEvent] = []
    let report = await fixture.coordinator.scan(context: fixture.context) { events.append($0) }
    XCTAssertNotNil(report)
    XCTAssertEqual(Set(events.map(\.generationID)), [report!.generationID])
    XCTAssertTrue(ScanModuleID.allCases.allSatisfy { report!.modules[$0]?.state.isTerminal == true })
}

func testCancellationReturnsNilInsteadOfPartialReport() async {
    let task = Task { await fixture.slowCoordinator.scan(context: fixture.context) { _ in } }
    task.cancel()
    XCTAssertNil(await task.value)
}

func testModuleRefreshChangesGenerationAndKeepsOtherTimestamps() {
    let old = fixture.completedReport
    let refreshed = old.replacing(
        module: .largeFiles,
        payload: .largeFiles(fixture.replacementDiskTree),
        completedAt: old.completedAt.addingTimeInterval(60)
    )
    XCTAssertNotEqual(refreshed.generationID, old.generationID)
    XCTAssertEqual(refreshed.modules[.applications]?.completedAt, old.modules[.applications]?.completedAt)
    XCTAssertGreaterThan(refreshed.modules[.largeFiles]!.completedAt!, old.modules[.largeFiles]!.completedAt!)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SystemScanCoordinatorTests`

Expected: compilation fails because the orchestrator does not exist.

- [ ] **Step 3: Implement the immutable aggregate report**

`SystemScanReport` stores generation metadata, `[ScanModuleID: ScanModuleStatus]`, cleanup candidates, `ApplicationInventory`, `DiskUsageTree`, `[AgentAssetRecord]`, and combined coverage. `isCommitEligible` requires every module to be terminal and at least one module to be completed or limited. `replacing` creates a fresh generation, replaces exactly one payload and timestamp, and leaves every other module payload and timestamp unchanged.

- [ ] **Step 4: Implement bounded parallel orchestration**

```swift
public struct SystemScanProgressEvent: Sendable, Equatable {
    public let generationID: UUID
    public let module: ScanModuleID
    public let state: ScanModuleState
    public let completedModules: Int
    public let totalModules: Int
    public let message: String?
}
```

Start one task per module in a throwing task group, emit scanning/terminal events, contain module errors as failed statuses, and assemble the report only after all tasks reach terminal states. If the parent task is cancelled, return `nil` and do not expose the partial builder.

- [ ] **Step 5: Merge payloads without duplicating large or Agent candidates**

General cleanup candidates come from cache/log/installer/developer scanners. Large-file candidates derive from `DiskUsageTree.largeFiles`. Agent cleanup candidates derive from unique `AgentAssetRecord.cleanupUnitURL` values. Sort every payload deterministically.

- [ ] **Step 6: Run coordinator and full core tests**

Run: `swift test --filter SystemScanCoordinatorTests && swift test`

Expected: PASS with deterministic module progress and no installed partial report on cancellation.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerCore/SystemScanReport.swift Sources/CleanerCore/SystemScanCoordinator.swift Tests/CleanerCoreTests/SystemScanCoordinatorTests.swift Sources/CoreContractChecks/ScannerContract.swift
git commit -m "feat: orchestrate complete system scans"
```

### Task 6: AppModel Report Ownership and Generation Invalidation

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Create: `Sources/CleanerCore/SystemScanSessionState.swift`
- Create: `Tests/CleanerCoreTests/SystemScanSessionStateTests.swift`
- Modify: `Sources/CoreContractChecks/AppNavigationContract.swift`

**Interfaces:**
- Consumes: `SystemScanCoordinator`, progress events, versioned report payloads.
- Produces: `AppModel.systemReport`, `scanProgressByModule`, `hasCompletedScan`, `startFullScan()`, `cancelScan()`, `refreshModule(_:)`, and `navigateToScan()`.

- [ ] **Step 1: Write failing pure-state tests**

```swift
func testCancelKeepsLastCompletedReport() {
    var state = SystemScanSessionState(completedReport: fixture.completedReport)
    state.begin(generationID: UUID())
    state.cancel()
    XCTAssertNotNil(state.completedReport)
    XCTAssertNil(state.inFlightGenerationID)
}

func testInstallingNewGenerationClearsDerivedPlanState() {
    var state = SystemScanSessionState(completedReport: fixture.completedReport, selectedIDs: [UUID()], pendingPlanID: UUID())
    state.install(fixture.replacementReport)
    XCTAssertTrue(state.selectedIDs.isEmpty)
    XCTAssertNil(state.pendingPlanID)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter SystemScanSessionStateTests`

Expected: compilation fails because the state reducer does not exist.

- [ ] **Step 3: Implement the pure session reducer**

The reducer owns the last completed report, in-flight generation, module progress, cancellation, and invalidation flags. It never owns file-system services or SwiftUI state.

- [ ] **Step 4: Replace independent app state with shared report projections**

In `AppModel`, replace `ScanReport?` plus separately bootstrapped application inventory with `SystemScanReport?`. Make `candidates`, `applications`, disk tree, Agent assets, coverage, and timestamps computed projections of that report. `bootstrap()` loads history and permissions only.

- [ ] **Step 5: Implement scan behavior**

`startFullScan()` retains the prior report, publishes per-module progress, installs only a commit-eligible report, selects the recommended cleanup IDs, stays on `.dashboard`, and sets `statusMessage`. `cancelScan()` cancels the task and preserves the prior report. `refreshModule(_:)` replaces one module, increments generation, and invalidates selection and pending-plan state.

- [ ] **Step 6: Run state, navigation, and full tests**

Run: `swift test --filter SystemScanSessionStateTests && swift test --filter AppNavigation && swift test`

Expected: PASS; scanning no longer changes navigation automatically and report replacement invalidates derived plan state.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerApp/AppModel.swift Sources/CleanerCore/SystemScanSessionState.swift Tests/CleanerCoreTests/SystemScanSessionStateTests.swift Sources/CoreContractChecks/AppNavigationContract.swift
git commit -m "feat: bind app state to shared scan report"
```

### Task 7: Overview Scan State Machine and Result-Page Empty States

**Files:**
- Modify: `Sources/CleanerApp/ContentView.swift`
- Modify: `Sources/CleanerApp/DashboardView.swift`
- Modify: `Sources/CleanerApp/Components.swift`
- Create: `Sources/CleanerApp/ScanRequiredView.swift`
- Modify: `Sources/CleanerApp/CleanupReviewView.swift`
- Modify: `Sources/CleanerApp/ApplicationsView.swift`
- Modify: `Sources/CleanerApp/DiskSpaceView.swift`
- Modify: `Sources/CleanerApp/AgentEnvironmentView.swift`
- Modify: `Sources/CleanerCore/AppNavigationPolicy.swift`
- Modify: `Sources/CoreContractChecks/AppNavigationContract.swift`

**Interfaces:**
- Consumes: `AppModel.hasCompletedScan`, module progress, report timestamps, and `navigateToScan()`.
- Produces: one Overview primary scan CTA, progress presentation, completed result hub, and reusable `ScanRequiredView`.

- [ ] **Step 1: Add failing navigation contract assertions**

```swift
precondition(!policy.showsGlobalScanToolbar)
precondition(policy.initialScanOwner == .dashboard)
precondition(policy.emptyStateAction(for: .cleanupCenter) == .returnToDashboard)
```

- [ ] **Step 2: Verify RED**

Run: `swift run CoreContractChecks`

Expected: compilation fails until the navigation policy exposes the new rules.

- [ ] **Step 3: Remove the global scan toolbar**

Delete the `.toolbar` block from `ContentView` and remove `ScanToolbar`. Keep only native `NavigationSplitView` controls.

- [ ] **Step 4: Implement the three Overview states**

- Pre-scan: large `开始完整扫描` button plus exact module coverage and read-only explanation.
- Scanning: four stable module rows, elapsed status, coverage messages, and `取消扫描`.
- Completed: result cards, completion time, warnings, primary `查看推荐方案`, and secondary `重新完整扫描`.

- [ ] **Step 5: Add reusable no-report routing**

```swift
struct ScanRequiredView: View {
    let destinationTitle: String
    let action: () -> Void
    // Renders 尚未扫描 and a bordered-prominent 返回概览开始扫描 button.
}
```

Gate Cleanup Center, Applications, Large Files, and Agent Environment on `hasCompletedScan`. Do not render mock counts or stale data as current.

- [ ] **Step 6: Build and run navigation contracts**

Run: `swift run CoreContractChecks && Scripts/build-app.sh`

Expected: PASS; toolbar magnifier-plus is absent, Overview owns the first scan, and no scan completion auto-navigation occurs.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerApp/ContentView.swift Sources/CleanerApp/DashboardView.swift Sources/CleanerApp/Components.swift Sources/CleanerApp/ScanRequiredView.swift Sources/CleanerApp/CleanupReviewView.swift Sources/CleanerApp/ApplicationsView.swift Sources/CleanerApp/DiskSpaceView.swift Sources/CleanerApp/AgentEnvironmentView.swift Sources/CleanerCore/AppNavigationPolicy.swift Sources/CoreContractChecks/AppNavigationContract.swift
git commit -m "feat: make overview the full scan entry"
```

### Task 8: Progressive Cleanup Category Review

**Files:**
- Create: `Sources/CleanerCore/CleanupStrategySelectionState.swift`
- Create: `Tests/CleanerCoreTests/CleanupStrategySelectionStateTests.swift`
- Modify: `Sources/CleanerCore/CleanupModeSelectionState.swift`
- Modify: `Sources/CleanerApp/GuidedCleanupView.swift`
- Modify: `Sources/CleanerApp/ReviewWorkspaceState.swift`
- Modify: `Sources/CoreContractChecks/CleanupModeContract.swift`
- Modify: `Sources/CoreContractChecks/ReviewInteractionContract.swift`

**Interfaces:**
- Produces: `CleanupStrategySelectionState`, tri-state category selection, item exclusions while retaining recommended/deep strategy, and generation binding.
- Consumes: report candidates, `CleanupRecommendationPolicy`, and `SystemScanReport.generationID`.

- [ ] **Step 1: Write failing strategy override tests**

```swift
func testExcludingRecommendedItemKeepsRecommendedStrategy() {
    var state = CleanupStrategySelectionState.recommended(candidates: fixture.candidates, generationID: fixture.generationID)
    state.toggle(fixture.recommendedID)
    XCTAssertEqual(state.strategy, .recommended)
    XCTAssertTrue(state.excludedBaseIDs.contains(fixture.recommendedID))
    XCTAssertTrue(state.isAdjusted)
}

func testBlockedItemCannotEnterSelection() {
    var state = CleanupStrategySelectionState.manual(generationID: fixture.generationID)
    state.toggle(fixture.blockedCandidate)
    XCTAssertFalse(state.selectedIDs.contains(fixture.blockedCandidate.id))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter CleanupStrategySelectionStateTests`

Expected: compilation fails because the strategy-plus-overrides state does not exist.

- [ ] **Step 3: Implement strategy and category tri-state logic**

Store `strategy`, `generationID`, `selectedIDs`, and `excludedBaseIDs`. Provide `categoryState(_:eligibleCandidates:) -> SelectionTriState` and `toggleCategory(_:eligibleCandidates:)`. A generation mismatch produces an empty invalid state.

- [ ] **Step 4: Replace summary-only rows with disclosure rows**

Remove the visible `方案` label while retaining `.accessibilityLabel("清理方案")`. Each category row shows tri-state checkbox, selected/eligible count, selected bytes, and a disclosure triangle. Expanded rows show concrete candidates with native checkboxes; clicking text focuses the inspector without toggling selection.

- [ ] **Step 5: Add retained and protected disclosure sections**

These sections are collapsed by default, display counts and bytes, and never offer selectable controls for protected items. Manual mode may add review/retained candidates but never blocked items.

- [ ] **Step 6: Run selection contracts and build**

Run: `swift test --filter CleanupStrategySelectionStateTests && swift run CoreContractChecks && Scripts/build-app.sh`

Expected: PASS; recommended/deep remain usable without review and exclusions do not switch the strategy label to manual.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerCore/CleanupStrategySelectionState.swift Tests/CleanerCoreTests/CleanupStrategySelectionStateTests.swift Sources/CleanerCore/CleanupModeSelectionState.swift Sources/CleanerApp/GuidedCleanupView.swift Sources/CleanerApp/ReviewWorkspaceState.swift Sources/CoreContractChecks/CleanupModeContract.swift Sources/CoreContractChecks/ReviewInteractionContract.swift
git commit -m "feat: add progressive cleanup review"
```

### Task 9: Precise Application Inventory UI

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CleanerApp/ApplicationsView.swift`
- Modify: `Sources/CleanerCore/ApplicationListFilter.swift`
- Modify: `Tests/CleanerCoreTests/ApplicationScannerTests.swift`
- Modify: `Sources/CoreContractChecks/ApplicationContract.swift`

**Interfaces:**
- Consumes: report-backed `ApplicationInventory` and inventory refresh.
- Produces: visible/total counts, clear-filter affordance, stable selected-row highlight, and coverage summary.

- [ ] **Step 1: Add failing filter-count and selection tests**

```swift
func testFilterSummaryExposesVisibleAndTotalCounts() {
    let summary = ApplicationListFilter(query: "ChatGPT", scope: .all).summary(for: fixture.apps)
    XCTAssertEqual(summary.visibleCount, 2)
    XCTAssertEqual(summary.totalCount, fixture.apps.count)
    XCTAssertTrue(summary.canClear)
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter ApplicationScannerTests`

Expected: compilation fails because filter summary does not exist.

- [ ] **Step 3: Implement inventory clarity**

Add `ApplicationFilterSummary`; expose `显示 N / 共 M 个应用`; show `清除筛选` whenever query or scope is active. On entry after launch, show all applications. If filtering hides the current selection, select the first visible app.

- [ ] **Step 4: Preserve native selection highlight and inspector detail**

Use `List(selection:)` tags as the source of truth and keep the explicit accent row background for clarity. Display name, bundle ID, running/protected state, version, exact path, and coverage warning. Keep `刷新应用` secondary and disabled while refreshing.

- [ ] **Step 5: Test and build**

Run: `swift test --filter ApplicationScannerTests && swift run CoreContractChecks && Scripts/build-app.sh`

Expected: PASS with visible/total counts and deterministic selection reconciliation.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerApp/AppModel.swift Sources/CleanerApp/ApplicationsView.swift Sources/CleanerCore/ApplicationListFilter.swift Tests/CleanerCoreTests/ApplicationScannerTests.swift Sources/CoreContractChecks/ApplicationContract.swift
git commit -m "feat: clarify complete application inventory"
```

### Task 10: Large-File Outline and Inspector

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Rewrite: `Sources/CleanerApp/DiskSpaceView.swift`
- Create: `Sources/CleanerApp/DiskUsageOutlineView.swift`
- Create: `Sources/CleanerCore/DiskUsageSelectionState.swift`
- Create: `Tests/CleanerCoreTests/DiskUsageSelectionStateTests.swift`

**Interfaces:**
- Consumes: report-backed `DiskUsageTree` and file-only cleanup candidates.
- Produces: directory disclosure/drill-down, breadcrumb, file selection, exact metadata inspector, and module refresh.

- [ ] **Step 1: Write failing file-only selection tests**

```swift
func testDirectoryCannotBecomeSelected() {
    var state = DiskUsageSelectionState()
    state.toggle(fixture.directoryNode)
    XCTAssertTrue(state.selectedFileURLs.isEmpty)
}

func testConcreteFileCanBecomeSelected() {
    var state = DiskUsageSelectionState()
    state.toggle(fixture.fileNode)
    XCTAssertEqual(state.selectedFileURLs, [fixture.fileNode.url])
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter DiskUsageSelectionStateTests`

Expected: compilation fails because selection state does not exist.

- [ ] **Step 3: Implement file-only selection adapter**

Map selected file URLs back to the report's concrete large-file candidates. Directory nodes expose only expansion and focus; no checkbox is rendered.

- [ ] **Step 4: Build the three-part page**

Render summary counts, `OutlineGroup`/native disclosure hierarchy, and inspector. Single click selects/focuses, double click expands a directory, breadcrumb reflects the focused branch, search matches paths, and the inspector shows own/recursive size, type, modified date, child count, readability, and safety explanation.

- [ ] **Step 5: Add secondary module refresh**

Show `刷新本模块` only after a completed full report. Display the large-file module timestamp and mark unchanged modules as older through the shared report timestamp component.

- [ ] **Step 6: Test and build**

Run: `swift test --filter DiskUsageSelectionStateTests && swift test --filter DiskUsageScannerTests && Scripts/build-app.sh`

Expected: PASS; directories are never selected and concrete files remain connected to immutable execution planning.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerApp/AppModel.swift Sources/CleanerApp/DiskSpaceView.swift Sources/CleanerApp/DiskUsageOutlineView.swift Sources/CleanerCore/DiskUsageSelectionState.swift Tests/CleanerCoreTests/DiskUsageSelectionStateTests.swift
git commit -m "feat: add large-file drill-down"
```

### Task 11: Agent Platform/Scope/Resource Hierarchy

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Rewrite: `Sources/CleanerApp/AgentEnvironmentView.swift`
- Create: `Sources/CleanerCore/AgentAssetGrouping.swift`
- Create: `Tests/CleanerCoreTests/AgentAssetGroupingTests.swift`
- Modify: `Sources/CoreContractChecks/AgentScannerContract.swift`

**Interfaces:**
- Consumes: report-backed `[AgentAssetRecord]`.
- Produces: `AgentAssetGroup`, provider/scope/resource filters, grouped cleanup units, and Agent-specific inspector facts.

- [ ] **Step 1: Write failing grouping tests**

```swift
func testHierarchyOrdersProviderThenScopeThenResource() {
    let groups = AgentAssetGrouping.group(fixture.assets)
    XCTAssertEqual(groups.first?.provider, .codex)
    XCTAssertTrue(groups.flatMap(\.scopes).allSatisfy { !$0.resourceGroups.isEmpty })
}

func testGroupSelectionExcludesProtectedAndActiveAssets() {
    let ids = AgentAssetGrouping.selectableIDs(in: fixture.mixedGroup)
    XCTAssertFalse(ids.contains(fixture.protectedID))
    XCTAssertFalse(ids.contains(fixture.activeID))
}
```

- [ ] **Step 2: Verify RED**

Run: `swift test --filter AgentAssetGroupingTests`

Expected: compilation fails because grouping utilities do not exist.

- [ ] **Step 3: Implement stable hierarchical groups**

Group by provider, then scope, then resource kind, using stable IDs derived from enum raw values. Each group computes item count, selectable count, selected count, bytes, and tri-state selection.

- [ ] **Step 4: Rebuild both Agent sections**

`清理建议` expands groups with recommended/deep cleanup units; `环境资产` shows all groups with protected groups collapsed. Add provider chips for Codex, Claude, Cursor, Trae, shared/global, and other detected roots; add provider, scope, resource, and eligibility filters.

- [ ] **Step 5: Add Agent-specific inspector**

Explain provider, scope, resource type, activity evidence, cleanup unit, retained siblings, recommendation cost, protection reason, and restore behavior. Active assets show `运行中` and have disabled selection.

- [ ] **Step 6: Test and build**

Run: `swift test --filter AgentAssetGroupingTests && swift test --filter AgentScannerTests && swift run CoreContractChecks && Scripts/build-app.sh`

Expected: PASS with structured provider ownership and no protected/active asset entering selection.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerApp/AppModel.swift Sources/CleanerApp/AgentEnvironmentView.swift Sources/CleanerCore/AgentAssetGrouping.swift Tests/CleanerCoreTests/AgentAssetGroupingTests.swift Sources/CoreContractChecks/AgentScannerContract.swift
git commit -m "feat: organize agent environment resources"
```

### Task 12: Cross-Page Safety, Accessibility, and Visual Verification

**Files:**
- Modify: `Sources/CleanerApp/Components.swift`
- Modify: `Sources/CleanerApp/ReviewWorkspaceView.swift`
- Modify: `Sources/CoreContractChecks/ReviewInteractionContract.swift`
- Create: `docs/verification/2026-08-25-precision-discovery-system-scan-verification.md`

**Interfaces:**
- Consumes: all previous tasks.
- Produces: consistent timestamp/coverage components, keyboard and accessibility semantics, final build evidence, and screenshot inventory.

- [ ] **Step 1: Add contract checks for accessibility-facing labels**

Assert that scan, category checkbox, directory disclosure, file checkbox, module refresh, filter count, and return-to-Overview actions all have stable non-empty labels. Assert tri-state values are `全部选择`, `部分选择`, or `未选择`.

- [ ] **Step 2: Run the full automated gate**

Run: `swift test && swift run CoreContractChecks && Scripts/build-app.sh && Scripts/verify-app.sh`

Expected: all commands exit 0; no cleanup execution occurs.

- [ ] **Step 3: Launch the built app and verify the pre-scan path**

Use Computer Use at a consistent window size. Verify the global magnifier-plus is absent, Overview shows `开始完整扫描`, and each result page routes back to Overview before the first report.

- [ ] **Step 4: Verify scanning and cancellation**

Start a full scan; verify four module rows update. Cancel once and confirm no results appear when no prior report exists. With a prior report, rescan and cancel; confirm the previous timestamp and results remain active.

- [ ] **Step 5: Verify completed cross-page interactions**

Confirm completion stays on Overview; open every result card; verify shared generation timestamp, application visible/total count and selected highlight, large-file directory expansion and file-only selection, Agent hierarchy and protection, cleanup category disclosure, exclusions, plan invalidation after selection changes, and page-scoped bottom action bar.

- [ ] **Step 6: Capture and inspect screenshots**

Capture Overview pre-scan/scanning/completed, Cleanup Center recommended/deep/expanded, Applications filtered/selected, Large Files expanded/inspected, Agent recommendations/assets, and limited-access states. Inspect spacing, truncation, focus, selected contrast, controls, and empty-state clarity.

- [ ] **Step 7: Write verification evidence and commit**

Document command outputs, interaction outcomes, screenshot paths, known limitations, and confirmation that no cleanup was executed.

```bash
git add Sources/CleanerApp/Components.swift Sources/CleanerApp/ReviewWorkspaceView.swift Sources/CoreContractChecks/ReviewInteractionContract.swift docs/verification/2026-08-25-precision-discovery-system-scan-verification.md
git commit -m "test: verify precision discovery experience"
```
