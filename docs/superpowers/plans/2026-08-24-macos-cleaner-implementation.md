# Native macOS Cleaner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a complete, independently implemented native macOS cleaner with safe universal cleanup, app uninstall, disk analysis, recovery history, and an Agent Workspace cleanup highlight.

**Architecture:** A SwiftPM workspace produces a SwiftUI executable and a reusable `CleanerCore` library. The core separates discovery, evidence classification, immutable planning, identity revalidation, recoverable execution, and audit history; the UI only drives typed domain APIs. A separately built helper target and XPC protocol reserve privileged operations, while the app remains fully useful in user-space without the helper.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Foundation, Combine, ServiceManagement, OSLog, CryptoKit, XCTest, Swift Package Manager, macOS 13+

**Spec:** `docs/superpowers/specs/2026-08-24-commercial-macos-cleaner-design.md`

## Global Constraints

- Minimum supported operating system is macOS 13.
- Product source, rules, UI, copy, icons, and structure are independently implemented and do not depend on Mole.
- Every destructive action follows `Scan → Plan → Review → Apply → Verify → Audit`.
- `safe` items may be selected by default, `review` items are unselected, and `blocked` items cannot be selected.
- User knowledge, credentials, custom Skills, MCP configuration, prompts, project memory, uncommitted code, untracked files, unpushed commits, and active tasks are never classified `safe`.
- Literal paths and resolved physical paths are validated; protected roots can never become execution targets.
- Execution revalidates file identity and activity immediately before mutation.
- Recoverable movement is the default; failure never falls back to permanent deletion.
- Full paths, file contents, prompts, conversations, credentials, and MCP responses are never sent as telemetry.
- The repository must build and test using installed Command Line Tools; Xcode-only signing and notarization remain release gates, not development prerequisites.
- The app bundle is assembled by a deterministic script and ad-hoc signed for local execution.

## File Structure

```text
Package.swift
Sources/
  CleanerCore/
    Models.swift                 # Domain value types and state machine
    FileSystem.swift             # Injectable filesystem facade and identities
    PathPolicy.swift             # Protected roots and canonical path validation
    Scanner.swift                # Scanner protocol, context, coordinator
    GeneralScanners.swift        # Cache, log, installer, developer, large-file scanners
    AgentScanners.swift          # Provider adapters and Agent asset classification
    ApplicationScanner.swift     # Installed apps and associated-file discovery
    Planning.swift               # Immutable plan construction and expiration
    Execution.swift              # Quarantine, trash, verification, cancellation
    HistoryStore.swift           # Atomic local operation history
    RuleStore.swift              # Versioned signed rule-pack loading and rollback
    HelperProtocol.swift         # Typed privileged request/response contracts
  CleanerApp/
    CleanerApp.swift             # SwiftUI application entry point
    AppModel.swift               # Main-actor orchestration and published state
    ContentView.swift            # Sidebar and adaptive three-column shell
    DashboardView.swift          # Summary and universal cleanup entry
    CleanupReviewView.swift      # Safe/review/blocked selection and inspector
    AgentWorkspaceView.swift     # Agent semantic asset map
    ApplicationsView.swift       # App uninstall review
    DiskSpaceView.swift          # Large-file analysis
    HistoryView.swift            # Receipts and recovery
    PermissionsView.swift        # Contextual permission state
    Components.swift             # Shared rows, badges, cards, empty/error states
  CleanerHelper/
    main.swift                   # NSXPC listener entry point
    HelperService.swift          # Caller verification and finite privileged operations
Tests/
  CleanerCoreTests/
    ModelsTests.swift
    PathPolicyTests.swift
    ScannerTests.swift
    AgentScannerTests.swift
    ApplicationScannerTests.swift
    PlanningTests.swift
    ExecutionTests.swift
    HistoryStoreTests.swift
    RuleStoreTests.swift
    HelperProtocolTests.swift
Scripts/
  build-app.sh                  # Release build and .app assembly
  verify-app.sh                 # Tests, bundle validation, signatures, smoke checks
Resources/
  AppInfo.plist
  HelperInfo.plist
  LaunchDaemon.plist
  Rules/base-rules.json
```

---

### Task 1: SwiftPM App and Domain Foundation

**Files:**
- Create: `Package.swift`
- Create: `Sources/CleanerCore/Models.swift`
- Create: `Tests/CleanerCoreTests/ModelsTests.swift`
- Create: `Sources/CleanerApp/CleanerApp.swift`
- Create: `Sources/CleanerApp/ContentView.swift`

**Interfaces:**
- Produces: `RiskLevel`, `CleanupCategory`, `Evidence`, `FileIdentity`, `CleanupCandidate`, `PlanItem`, `CleanupPlan`, `OperationResult`, `OperationReceipt`.
- Produces: runnable `CleanerApp` SwiftPM executable importing SwiftUI.

- [ ] **Step 1: Write failing model tests**

```swift
func testRiskDefaults() {
    XCTAssertTrue(RiskLevel.safe.isSelectableByDefault)
    XCTAssertFalse(RiskLevel.review.isSelectableByDefault)
    XCTAssertFalse(RiskLevel.blocked.isSelectable)
}

func testCandidateRoundTripPreservesIdentity() throws {
    let candidate = CleanupCandidate.fixture(identity: .init(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory))
    let data = try JSONEncoder().encode(candidate)
    XCTAssertEqual(try JSONDecoder().decode(CleanupCandidate.self, from: data), candidate)
}
```

- [ ] **Step 2: Run the tests and verify the target is absent**

Run: `swift test --filter ModelsTests`
Expected: FAIL because `Package.swift` and model types do not exist.

- [ ] **Step 3: Create the package and exact domain types**

```swift
public enum RiskLevel: String, Codable, Sendable, CaseIterable {
    case safe, review, blocked
    public var isSelectableByDefault: Bool { self == .safe }
    public var isSelectable: Bool { self != .blocked }
}

public struct FileIdentity: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable { case file, directory, symbolicLink, other }
    public let device: UInt64
    public let inode: UInt64
    public let size: UInt64
    public let modificationTime: Int64
    public let kind: Kind
}
```

- [ ] **Step 4: Add a minimal native SwiftUI shell**

```swift
@main
struct CleanerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        .defaultSize(width: 1280, height: 820)
    }
}
```

- [ ] **Step 5: Verify tests and executable compilation**

Run: `swift test && swift build --product CleanerApp`
Expected: PASS and `.build/debug/CleanerApp` exists.

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources Tests
git commit -m "feat: add native cleaner domain foundation"
```

### Task 2: Filesystem Facade and Path Safety

**Files:**
- Create: `Sources/CleanerCore/FileSystem.swift`
- Create: `Sources/CleanerCore/PathPolicy.swift`
- Create: `Tests/CleanerCoreTests/PathPolicyTests.swift`

**Interfaces:**
- Produces: `FileSystemAccess` protocol and `LocalFileSystem` actor.
- Produces: `PathPolicy.validateCandidate(_:) throws -> ValidatedPath`.
- Consumes: `FileIdentity` from Task 1.

- [ ] **Step 1: Write rejection tests for protected and adversarial paths**

```swift
func testRejectsRootsTraversalAndControlCharacters() {
    for path in ["/", "/System", "/Users", NSHomeDirectory(), "/tmp/../System", "/tmp/a\nb"] {
        XCTAssertThrowsError(try policy.validateCandidate(URL(fileURLWithPath: path)))
    }
}

func testNeverAllowsAgentRootItself() {
    XCTAssertThrowsError(try policy.validateCandidate(home.appending(path: ".codex")))
    XCTAssertThrowsError(try policy.validateCandidate(home.appending(path: ".claude")))
}
```

- [ ] **Step 2: Verify the tests fail**

Run: `swift test --filter PathPolicyTests`
Expected: FAIL because `PathPolicy` is undefined.

- [ ] **Step 3: Implement canonical deny-first validation**

```swift
public struct ValidatedPath: Hashable, Sendable {
    public let literal: URL
    public let physical: URL
}

public struct PathPolicy: Sendable {
    public func validateCandidate(_ url: URL) throws -> ValidatedPath {
        guard url.path.hasPrefix("/"), !url.pathComponents.contains(".."),
              url.path.unicodeScalars.allSatisfy({ !$0.properties.isControl }) else {
            throw PathPolicyError.invalidSyntax
        }
        let physical = url.resolvingSymlinksInPath().standardizedFileURL
        try rejectProtected(url.standardizedFileURL)
        try rejectProtected(physical)
        return ValidatedPath(literal: url.standardizedFileURL, physical: physical)
    }
}
```

- [ ] **Step 4: Add identity capture and injectable filesystem methods**

`FileSystemAccess` must expose `identity(at:)`, `children(of:)`, `isReadable(_:)`, `isWritable(_:)`, `move(_:to:)`, `removeEmptyDirectory(_:)`, and `trash(_:)` without exposing arbitrary command execution.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter PathPolicyTests && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/FileSystem.swift Sources/CleanerCore/PathPolicy.swift Tests/CleanerCoreTests/PathPolicyTests.swift
git commit -m "feat: enforce protected path boundaries"
```

### Task 3: Scan Coordination and Universal Scanners

**Files:**
- Create: `Sources/CleanerCore/Scanner.swift`
- Create: `Sources/CleanerCore/GeneralScanners.swift`
- Create: `Tests/CleanerCoreTests/ScannerTests.swift`

**Interfaces:**
- Produces: `Scanner`, `ScanContext`, `ScanProgress`, `ScanCoordinator`.
- Produces scanners: `UserCacheScanner`, `LogScanner`, `InstallerScanner`, `DeveloperArtifactScanner`, `LargeFileScanner`.
- Consumes: `FileSystemAccess`, `PathPolicy`, and `CleanupCandidate`.

- [ ] **Step 1: Write scanner contract and risk tests**

```swift
func testRecentCacheIsReviewAndOldInactiveCacheIsSafe() async throws {
    let results = try await scanner.scan(context: fixture.context)
    XCTAssertEqual(results[id: "recent"].risk, .review)
    XCTAssertEqual(results[id: "old"].risk, .safe)
}

func testLargeFilesAreNeverSafeBySizeAlone() async throws {
    let results = try await largeFileScanner.scan(context: fixture.context)
    XCTAssertTrue(results.allSatisfy { $0.risk != .safe })
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter ScannerTests`
Expected: FAIL because scanner types are undefined.

- [ ] **Step 3: Implement the scanner protocol and coordinator**

```swift
public protocol Scanner: Sendable {
    var id: String { get }
    var category: CleanupCategory { get }
    func scan(context: ScanContext) async throws -> [CleanupCandidate]
}

public actor ScanCoordinator {
    public func scan(using scanners: [any Scanner], context: ScanContext) async -> ScanReport
}
```

The coordinator uses a throwing task group with an I/O concurrency limit, reports per-scanner failures, and never mutates files.

- [ ] **Step 4: Implement conservative universal scanners**

Use standard macOS directories. Cache and log scanners classify by age and activity; installer scanning is limited to user Downloads/Desktop and known extensions; developer scanning uses explicit known cache roots; large files remain `review`.

- [ ] **Step 5: Verify cancellation and no-write behavior**

Run: `swift test --filter ScannerTests && swift test`
Expected: PASS, including cancellation tests that assert zero filesystem mutation calls.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/Scanner.swift Sources/CleanerCore/GeneralScanners.swift Tests/CleanerCoreTests/ScannerTests.swift
git commit -m "feat: add universal cleanup scanners"
```

### Task 4: Agent Workspace Semantic Scanning

**Files:**
- Create: `Sources/CleanerCore/AgentScanners.swift`
- Create: `Tests/CleanerCoreTests/AgentScannerTests.swift`

**Interfaces:**
- Produces: `AgentProviderAdapter`, `AgentAssetKind`, `AgentAssetRelation`, `AgentWorkspaceScanner`.
- Produces adapters for Codex-style, Claude-style, Cursor-style, generic MCP, and Git worktree assets.
- Consumes: Scanner types from Task 3.

- [ ] **Step 1: Write protection-first Agent tests**

```swift
func testCustomSkillsPromptsAndMCPConfigAreBlocked() async throws {
    let results = try await scanner.scan(context: fixture.context)
    XCTAssertEqual(results[pathSuffix: "SKILL.md"].risk, .blocked)
    XCTAssertEqual(results[pathSuffix: "mcp.json"].risk, .blocked)
    XCTAssertEqual(results[pathSuffix: "AGENTS.md"].risk, .blocked)
}

func testFinishedSandboxCacheCanBeSafeButSessionIsReview() async throws {
    let results = try await scanner.scan(context: fixture.context)
    XCTAssertEqual(results[id: "finished-sandbox-cache"].risk, .safe)
    XCTAssertEqual(results[id: "old-session"].risk, .review)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter AgentScannerTests`
Expected: FAIL because Agent scanner types are undefined.

- [ ] **Step 3: Implement provider discovery without executable configuration**

```swift
public protocol AgentProviderAdapter: Sendable {
    var providerID: String { get }
    func discoverRoots(context: ScanContext) async -> [AgentRoot]
    func classify(url: URL, root: AgentRoot, context: ScanContext) async -> AgentClassification
}
```

Adapters parse only the minimum configuration structure needed to identify references. They never expand environment variables, invoke MCP commands, read credential values, or mark a provider root as removable.

- [ ] **Step 4: Implement MCP, Skill, model-cache, and worktree rules**

Worktrees are `blocked` when dirty, untracked, locked, in use, mid-operation, unpushed, or unverifiable. MCP configuration and credentials are `blocked`; stale reproducible runtime caches are `review`; custom Skills are `blocked`.

- [ ] **Step 5: Run Agent and full suites**

Run: `swift test --filter AgentScannerTests && swift test`
Expected: PASS with zero tests classifying protected Agent knowledge as `safe`.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/AgentScanners.swift Tests/CleanerCoreTests/AgentScannerTests.swift
git commit -m "feat: add agent workspace cleanup discovery"
```

### Task 5: Application Discovery and Safe Uninstall Planning

**Files:**
- Create: `Sources/CleanerCore/ApplicationScanner.swift`
- Create: `Tests/CleanerCoreTests/ApplicationScannerTests.swift`

**Interfaces:**
- Produces: `InstalledApplication`, `ApplicationAssociation`, `ApplicationScanner`, `UninstallPlanner`.
- Consumes: `PathPolicy`, `CleanupCandidate`, `FileSystemAccess`.

- [ ] **Step 1: Write association and shared-data tests**

```swift
func testBundleIDAssociationDoesNotMatchPrefixCollision() async throws {
    let associations = try await scanner.associations(for: fixture.app(bundleID: "com.example.app"))
    XCTAssertFalse(associations.contains { $0.url.lastPathComponent.contains("com.example.app2") })
}

func testSharedOrUserContentIsBlocked() async throws {
    let plan = try await planner.planUninstall(fixture.app)
    XCTAssertTrue(plan.items.filter(\.containsUserData).allSatisfy { $0.risk == .blocked })
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter ApplicationScannerTests`
Expected: FAIL because application types are undefined.

- [ ] **Step 3: Implement application enumeration and exact ownership evidence**

Enumerate `/Applications`, `~/Applications`, and valid Homebrew app locations. Read bundle metadata using Foundation. Discover exact bundle-ID/name matches in standard support, cache, preference, saved-state, launch-agent, and helper locations while guarding boundary collisions and shared roots.

- [ ] **Step 4: Build review-only uninstall plans**

App bundle and exact recoverable associations are `review`; shared data, documents, active apps, system apps, ambiguous helpers, and protected roots are `blocked`.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter ApplicationScannerTests && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/ApplicationScanner.swift Tests/CleanerCoreTests/ApplicationScannerTests.swift
git commit -m "feat: add application uninstall discovery"
```

### Task 6: Immutable Planning and Recoverable Execution

**Files:**
- Create: `Sources/CleanerCore/Planning.swift`
- Create: `Sources/CleanerCore/Execution.swift`
- Create: `Tests/CleanerCoreTests/PlanningTests.swift`
- Create: `Tests/CleanerCoreTests/ExecutionTests.swift`

**Interfaces:**
- Produces: `PlanBuilder.build(candidates:selectedIDs:now:) throws -> CleanupPlan`.
- Produces: `CleanupExecutor.execute(plan:progress:) async -> OperationReceipt`.
- Produces: `CleanupExecutor.restore(receipt:) async -> RestoreReceipt`.

- [ ] **Step 1: Write plan expiration and selection tests**

```swift
func testBlockedCandidateCannotEnterPlan() {
    XCTAssertThrowsError(try builder.build(candidates: [fixture.blocked], selectedIDs: [fixture.blocked.id], now: clock.now))
}

func testPlanExpiresAndRuleVersionChangeInvalidatesExecution() async {
    let receipt = await executor.execute(plan: fixture.expiredPlan, progress: { _ in })
    XCTAssertEqual(receipt.overallStatus, .rejected)
}
```

- [ ] **Step 2: Write identity-race and no-fallback tests**

```swift
func testChangedIdentityIsSkippedWithoutMutation() async {
    filesystem.identityOverride = fixture.changedIdentity
    let receipt = await executor.execute(plan: fixture.plan, progress: { _ in })
    XCTAssertEqual(receipt.results.first?.status, .skippedIdentityChanged)
    XCTAssertTrue(filesystem.mutations.isEmpty)
}

func testTrashFailureNeverCallsPermanentDelete() async {
    filesystem.trashError = TestError.denied
    _ = await executor.execute(plan: fixture.plan, progress: { _ in })
    XCTAssertFalse(filesystem.mutations.contains(.permanentDelete))
}
```

- [ ] **Step 3: Verify tests fail**

Run: `swift test --filter PlanningTests && swift test --filter ExecutionTests`
Expected: FAIL because planning and execution types are undefined.

- [ ] **Step 4: Implement plan binding and executor state machine**

Bind plan ID, created/expiry timestamps, engine/rule/macOS versions, exact identities, chosen action, evidence hash, and risk. Revalidate policy, identity, activity, rule revocation, and destination conflicts for every item immediately before mutation.

- [ ] **Step 5: Implement quarantine and conflict-safe restore**

Move recoverable items into an app-owned quarantine directory keyed by plan ID. Store original path and identity. Restore never overwrites; it reports conflict and selects a sibling recovery path.

- [ ] **Step 6: Run focused and full tests**

Run: `swift test --filter PlanningTests && swift test --filter ExecutionTests && swift test`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerCore/Planning.swift Sources/CleanerCore/Execution.swift Tests/CleanerCoreTests/PlanningTests.swift Tests/CleanerCoreTests/ExecutionTests.swift
git commit -m "feat: add recoverable cleanup execution"
```

### Task 7: Atomic History and Signed Rule Store

**Files:**
- Create: `Sources/CleanerCore/HistoryStore.swift`
- Create: `Sources/CleanerCore/RuleStore.swift`
- Create: `Resources/Rules/base-rules.json`
- Create: `Tests/CleanerCoreTests/HistoryStoreTests.swift`
- Create: `Tests/CleanerCoreTests/RuleStoreTests.swift`

**Interfaces:**
- Produces: `HistoryStore.append(_:)`, `receipts()`, `receipt(id:)`.
- Produces: `RuleStore.loadBundled()`, `install(update:)`, `rollback()`, `isRevoked(ruleID:)`.

- [ ] **Step 1: Write atomic-history and recovery tests**

```swift
func testInterruptedWritePreservesPreviousHistory() async throws {
    try await store.append(fixture.receipt1)
    filesystem.failNextAtomicRename = true
    await XCTAssertThrowsErrorAsync { try await store.append(fixture.receipt2) }
    XCTAssertEqual(try await store.receipts(), [fixture.receipt1])
}
```

- [ ] **Step 2: Write rule signature and rollback tests**

```swift
func testRejectsInvalidSignatureAndKeepsCurrentRules() async throws {
    let before = try await store.currentVersion()
    await XCTAssertThrowsErrorAsync { try await store.install(update: fixture.tamperedUpdate) }
    XCTAssertEqual(try await store.currentVersion(), before)
}
```

- [ ] **Step 3: Verify tests fail**

Run: `swift test --filter HistoryStoreTests && swift test --filter RuleStoreTests`
Expected: FAIL because store types are undefined.

- [ ] **Step 4: Implement atomic JSON history and CryptoKit verification**

Write to a same-directory temporary file, synchronize, and atomically replace. Decode rule packs with a fixed schema; verify detached Ed25519 signatures using an embedded public key; keep current and previous valid packs; never load partial updates.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter HistoryStoreTests && swift test --filter RuleStoreTests && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/HistoryStore.swift Sources/CleanerCore/RuleStore.swift Resources Tests/CleanerCoreTests
git commit -m "feat: add audit history and signed rules"
```

### Task 8: Typed Privileged Helper Boundary

**Files:**
- Create: `Sources/CleanerCore/HelperProtocol.swift`
- Create: `Sources/CleanerHelper/main.swift`
- Create: `Sources/CleanerHelper/HelperService.swift`
- Create: `Resources/HelperInfo.plist`
- Create: `Resources/LaunchDaemon.plist`
- Create: `Tests/CleanerCoreTests/HelperProtocolTests.swift`

**Interfaces:**
- Produces finite `HelperOperation` cases and `CapabilityToken`.
- Produces `PrivilegedHelperClient` protocol with no arbitrary command API.

- [ ] **Step 1: Write protocol rejection tests**

```swift
func testTokenCannotAuthorizeDifferentPathOrReplay() async {
    let token = fixture.token(path: "/Library/Caches/example")
    XCTAssertEqual(await service.perform(.moveToQuarantine(path: "/Library/Caches/other"), token: token), .rejected)
    XCTAssertEqual(await service.perform(.moveToQuarantine(path: token.path), token: token), .accepted)
    XCTAssertEqual(await service.perform(.moveToQuarantine(path: token.path), token: token), .rejected)
}
```

- [ ] **Step 2: Verify tests fail**

Run: `swift test --filter HelperProtocolTests`
Expected: FAIL because helper protocol types are undefined.

- [ ] **Step 3: Implement finite Codable requests and token validation**

```swift
public enum HelperOperation: Codable, Sendable, Equatable {
    case inspect(path: String)
    case moveToQuarantine(path: String, destination: String)
    case removeOwnedQuarantine(path: String)
    case unloadVerifiedService(label: String, plistPath: String)
}
```

Tokens bind caller requirement, plan ID, allowed operation digest, expiry, nonce, and candidate identities. The service consumes nonces once and reruns `PathPolicy` and identity checks.

- [ ] **Step 4: Implement XPC listener and caller audit-token verification**

The helper exports one protocol method accepting encoded `HelperRequest` and returning `HelperResponse`. It rejects callers whose code-signing designated requirement does not match the app.

- [ ] **Step 5: Run tests and compile helper**

Run: `swift test --filter HelperProtocolTests && swift build --product CleanerHelper`
Expected: PASS and helper executable exists. Task 12 verifies bundle placement and local signing; the documented production gate verifies Developer ID registration and notarization on a signing-enabled machine.

- [ ] **Step 6: Commit**

```bash
git add Sources/CleanerCore/HelperProtocol.swift Sources/CleanerHelper Resources Tests/CleanerCoreTests/HelperProtocolTests.swift
git commit -m "feat: define privileged helper boundary"
```

### Task 9: SwiftUI Application State and Complete Interaction

**Files:**
- Create: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CleanerApp/ContentView.swift`
- Create: `Sources/CleanerApp/DashboardView.swift`
- Create: `Sources/CleanerApp/CleanupReviewView.swift`
- Create: `Sources/CleanerApp/AgentWorkspaceView.swift`
- Create: `Sources/CleanerApp/ApplicationsView.swift`
- Create: `Sources/CleanerApp/DiskSpaceView.swift`
- Create: `Sources/CleanerApp/HistoryView.swift`
- Create: `Sources/CleanerApp/PermissionsView.swift`
- Create: `Sources/CleanerApp/Components.swift`

**Interfaces:**
- Produces: `@MainActor final class AppModel: ObservableObject`.
- Consumes every core service through initializer-injected protocols.

- [ ] **Step 1: Add model tests for selection invariants**

In `ModelsTests`, verify safe candidates start selected, review candidates start unselected, blocked candidates cannot toggle, totals use only selected candidates, and scan cancellation never creates a plan.

- [ ] **Step 2: Implement AppModel state machine**

```swift
@MainActor
final class AppModel: ObservableObject {
    enum Phase: Equatable { case idle, scanning, reviewing, executing, completed, failed(String) }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var report: ScanReport?
    @Published var selectedIDs: Set<CleanupCandidate.ID> = []
    @Published var selection: SidebarDestination = .dashboard
}
```

- [ ] **Step 3: Build the adaptive macOS shell**

Use `NavigationSplitView` with universal destinations: Overview, Smart Cleanup, Applications, Disk Space, Developer Tools, Agent Workspace, History, and Settings. Agent Workspace is highlighted but does not replace universal cleanup.

- [ ] **Step 4: Implement three safety states and inspector**

Rows use checkbox + label + icon + accessible text. `safe` is selectable, `review` requires explicit opt-in, `blocked` is locked. The inspector explains evidence, impact, rebuild cost, recoverability, and permission needs.

- [ ] **Step 5: Implement scan, execution, receipt, and restore states**

Include empty, scanning, permission-limited, review, confirmation, executing, partial failure, completed, history, restore, and restore-conflict experiences. Never use a fear score or destructive red primary button.

- [ ] **Step 6: Verify compile and core tests**

Run: `swift test && swift build --product CleanerApp`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/CleanerApp Tests/CleanerCoreTests/ModelsTests.swift
git commit -m "feat: build complete native cleaner interface"
```

### Task 10: Permissions, App Uninstall, and Recovery Wiring

**Files:**
- Modify: `Sources/CleanerApp/AppModel.swift`
- Modify: `Sources/CleanerApp/ApplicationsView.swift`
- Modify: `Sources/CleanerApp/HistoryView.swift`
- Modify: `Sources/CleanerApp/PermissionsView.swift`
- Create: `Sources/CleanerCore/PermissionStatus.swift`
- Create: `Tests/CleanerCoreTests/PermissionStatusTests.swift`

**Interfaces:**
- Produces: `PermissionStatusService.snapshot() -> PermissionSnapshot`.
- Connects uninstall and restore UI to Tasks 5–7.

- [ ] **Step 1: Write permission degradation tests**

Verify denied Full Disk Access yields `.limited` with affected categories, does not fail all scanning, and never repeatedly requests authorization.

- [ ] **Step 2: Implement read-only permission diagnosis**

Probe representative protected locations without reading content. Return capability differences and a System Settings deep link; opening settings occurs only after a user action.

- [ ] **Step 3: Wire uninstall plans and running-app protection**

Applications show bundle, exact associations, shared/protected data, running status, and recoverability. Running apps remain blocked; the app never force-quits them.

- [ ] **Step 4: Wire history receipts and conflict-safe restore**

History is always accessible regardless of license state. Restore explains conflicts and never overwrites existing files.

- [ ] **Step 5: Run tests and build**

Run: `swift test && swift build --product CleanerApp`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: connect permissions uninstall and recovery"
```

### Task 11: Local Licensing, Updates, and Privacy Controls

**Files:**
- Create: `Sources/CleanerCore/LicenseStore.swift`
- Create: `Sources/CleanerCore/UpdateService.swift`
- Create: `Sources/CleanerCore/PrivacySettings.swift`
- Create: `Tests/CleanerCoreTests/LicenseStoreTests.swift`
- Create: `Tests/CleanerCoreTests/UpdateServiceTests.swift`
- Modify: `Sources/CleanerApp/PermissionsView.swift`

**Interfaces:**
- Produces offline-verifiable signed license claims with trial and paid capabilities.
- Produces signed update-manifest verification without applying untrusted payloads.

- [ ] **Step 1: Write license safety-right tests**

Verify expired trials can still open history, restore quarantined items, remove the helper, and export receipts. Only premium scans and new cleanup execution are gated.

- [ ] **Step 2: Write update signature and downgrade tests**

Verify tampered manifests, hash mismatches, incompatible macOS versions, and unapproved downgrades are rejected before download or install.

- [ ] **Step 3: Implement CryptoKit-signed local license validation**

Store only signed claims and receipt metadata. No embedded private key. Restore and safety rights bypass commercial feature gates.

- [ ] **Step 4: Implement signed update metadata**

Update service validates version, URL allow-list, artifact hash, signature, and minimum OS.

- [ ] **Step 5: Run focused and full tests**

Run: `swift test --filter LicenseStoreTests && swift test --filter UpdateServiceTests && swift test`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources Tests
git commit -m "feat: add licensing update and privacy controls"
```

### Task 12: App Bundle, Smoke Verification, and Release Gates

**Files:**
- Create: `Resources/AppInfo.plist`
- Create: `Scripts/build-app.sh`
- Create: `Scripts/verify-app.sh`
- Modify: `README.md`

**Interfaces:**
- Produces: `build/SuperCleaner.app` runnable on the current Mac.
- Produces: a single verification command, `./Scripts/verify-app.sh`.

- [ ] **Step 1: Write bundle assertions before the build script**

`verify-app.sh` must fail unless the app contains `Contents/Info.plist`, `Contents/MacOS/CleanerApp`, bundled rules, helper executable, correct minimum system version, and a valid local code signature.

- [ ] **Step 2: Run verification and confirm failure**

Run: `chmod +x Scripts/verify-app.sh && ./Scripts/verify-app.sh`
Expected: FAIL because the app bundle does not exist.

- [ ] **Step 3: Implement deterministic SwiftPM app assembly**

`build-app.sh` runs release tests, builds app/helper, creates the standard bundle layout, copies resources, writes no mutable files inside the sealed bundle at runtime, ad-hoc signs nested code inside-out, and produces `build/SuperCleaner.app`.

- [ ] **Step 4: Add smoke checks**

Launch the executable with `--smoke-test` to initialize stores in a temporary home, run fixture-backed scanning, build a plan, execute only inside the fixture directory, verify receipt creation, restore it, and exit zero without opening a window.

- [ ] **Step 5: Run complete verification**

Run: `./Scripts/build-app.sh && ./Scripts/verify-app.sh`
Expected: all Swift tests pass, app and helper compile, bundle checks pass, signature verifies, smoke cleanup/restore passes, and no protected real path is modified.

- [ ] **Step 6: Document production-only release gates**

README must list: install full Xcode, configure Developer ID Application and Installer identities, register the helper, archive, notarize with `notarytool`, staple, verify Gatekeeper on a clean Mac, and complete an external security audit before enabling privileged cleanup by default.

- [ ] **Step 7: Commit**

```bash
git add Resources Scripts README.md
git commit -m "build: package and verify native macOS app"
```

### Task 13: Requirement-by-Requirement Completion Audit

**Files:**
- Create: `docs/verification/2026-08-24-macos-cleaner-verification.md`
- Modify only if audit finds a concrete gap: implementation or test files above.

**Interfaces:**
- Produces authoritative evidence for every V1 capability and safety invariant in the spec.

- [ ] **Step 1: Build a coverage matrix from every spec section**

For each requirement, record implementation file, test name, runtime evidence, and verdict: proven, contradicted, incomplete, or missing.

- [ ] **Step 2: Run all verification commands fresh**

Run: `swift test && ./Scripts/build-app.sh && ./Scripts/verify-app.sh`
Expected: zero failures.

- [ ] **Step 3: Exercise the actual app on this Mac**

Run the built app, verify universal and Agent navigation, perform a scan, inspect all three safety states, execute a fixture-only cleanup, inspect history, restore, cancel a scan, and verify permission-limited behavior. Record screenshots and logs without private paths.

- [ ] **Step 4: Fix every incomplete or contradicted requirement**

Add targeted failing tests before each fix, implement the smallest complete correction, and rerun full verification after each group.

- [ ] **Step 5: Commit the audit**

```bash
git add docs/verification Sources Tests Scripts
git commit -m "docs: verify complete macOS cleaner functionality"
```
