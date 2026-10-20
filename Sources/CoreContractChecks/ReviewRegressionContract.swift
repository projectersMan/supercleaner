import CleanerCore
import Foundation

private actor ReviewInterleavingFileSystem: FileSystemAccess {
    private var entries: [String: FileIdentity]
    private let pausePath: String
    private var paused = false
    private var continuation: CheckedContinuation<Void, Never>?
    private let onIdentity: @Sendable () -> Void
    private let onCreateDirectory: @Sendable () -> Void
    init(entries: [URL: FileIdentity], pause: URL, onIdentity: @escaping @Sendable () -> Void = {},
         onCreateDirectory: @escaping @Sendable () -> Void = {}) {
        self.entries = Dictionary(uniqueKeysWithValues: entries.map { ($0.key.path, $0.value) })
        pausePath = pause.path
        self.onIdentity = onIdentity; self.onCreateDirectory = onCreateDirectory
    }
    func identity(at url: URL) throws -> FileIdentity {
        guard let identity = entries[url.path] else { throw FileSystemError.missing(url) }
        onIdentity()
        return identity
    }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { true }
    func fileExists(_ url: URL) async -> Bool {
        if url.path == pausePath, !paused {
            paused = true
            await withCheckedContinuation { continuation = $0 }
        }
        return entries[url.path] != nil
    }
    func waitUntilPaused() async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !paused {
            guard ContinuousClock.now < deadline else { throw ProcessFailure.timedOut }
            try await Task.sleep(for: .milliseconds(1))
        }
    }
    func release() { continuation?.resume(); continuation = nil }
    func move(_ source: URL, to destination: URL) throws {
        guard entries[destination.path] == nil, let identity = entries.removeValue(forKey: source.path) else { throw FileSystemError.missing(source) }
        entries[destination.path] = identity
    }
    func remove(_ source: URL) throws {
        guard entries.removeValue(forKey: source.path) != nil else { throw FileSystemError.missing(source) }
    }
    func createDirectory(_ url: URL) { onCreateDirectory() }
    func removeEmptyDirectory(_ url: URL) { }
    func trash(_ url: URL) -> URL { url }
}

private actor ReviewOperationCompletion {
    private(set) var finished = false
    func finish() { finished = true }
}

private final class ReviewFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.withLock { value } }
    func expire() { lock.withLock { value = Date(timeIntervalSince1970: 1_301) } }
}

private actor ReviewDeclinedPrivilege: PrivilegedApplicationOperations {
    let clock: ReviewFixtureClock
    let expireOnMove: Bool
    private(set) var moveRequests = 0
    init(clock: ReviewFixtureClock, expireOnMove: Bool) {
        self.clock = clock; self.expireOnMove = expireOnMove
    }
    func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) async throws -> Bool {
        moveRequests += 1
        if expireOnMove { clock.expire() }
        return false
    }
    func restore(source: URL, destination: URL, planID: UUID) async throws -> Bool { false }
    func purge(source: URL, planID: UUID) async throws -> Bool { false }
}

private enum ReviewExpiryPoint: CaseIterable { case validation, activity, identity, quarantineCreation, privilegeFallback }

func runReviewExpiryRegressionContracts() async throws {
    let home = URL(fileURLWithPath: "/Users/expiry-fixture")
    let source = home.appendingPathComponent("Library/Caches/payload")
    let quarantine = home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine")
    let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
    let candidate = CleanupCandidate(url: source, displayName: "payload", category: .cache, bytes: 3, risk: .review,
        evidence: [], identity: identity, source: .general, lastAccessDate: nil, isActive: false)
    for point in ReviewExpiryPoint.allCases {
        let clock = ReviewFixtureClock()
        let privilege = ReviewDeclinedPrivilege(clock: clock, expireOnMove: point == .privilegeFallback)
        let fs = ReviewInterleavingFileSystem(entries: [source: identity], pause: home.appendingPathComponent("unused"),
            onIdentity: { if point == .identity { clock.expire() } },
            onCreateDirectory: { if point == .quarantineCreation { clock.expire() } })
        let plan = try PlanBuilder(ruleVersion: "review").build(candidates: [candidate], selectedIDs: [candidate.id], now: clock.now())
        let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home), quarantineRoot: quarantine,
            currentRuleVersion: "review", now: clock.now,
            isActive: { _ in if point == .activity { clock.expire() }; return false },
            loadProtection: { ProtectionPolicy(homeDirectory: home) },
            validateCandidate: { _ in if point == .validation { clock.expire() } },
            privilegedApplications: privilege)
        let receipt = await executor.execute(plan: plan)
        let originalExists = await fs.fileExists(source)
        let privilegedRequests = await privilege.moveRequests
        require(plan.isExpired(at: clock.now()) && originalExists && receipt.results.first?.status == .skippedProtected,
                "plan expiring during \(point) must not move content locally or send it to Helper")
        require(privilegedRequests == (point == .privilegeFallback ? 1 : 0),
                "plan expiring during \(point) must not begin a new privileged move")
    }
    print("PASS: plan expiry after validation/activity/identity/directory preparation/privilege fallback refuses movement")
}

/// Limit all discovery to the fixture home; never follow environment roots into
/// the real user's Agent data. Permission failures are injected at the FS seam.
private struct ReviewScanFileSystem: FileSystemAccess {
    let home: URL
    var unreadableDirectory: URL?
    var unverifiablePath: URL?
    private let local = LocalFileSystem()
    private func contains(_ url: URL) -> Bool {
        let path = url.resolvingSymlinksInPath().path
        let root = home.resolvingSymlinksInPath().path
        return path == root || path.hasPrefix(root + "/")
    }
    func identity(at url: URL) async throws -> FileIdentity {
        guard contains(url), url.resolvingSymlinksInPath().path != unverifiablePath?.resolvingSymlinksInPath().path else { throw FileSystemError.unreadableContent(url) }
        return try await local.identity(at: url)
    }
    func children(of url: URL) async throws -> [URL] {
        guard contains(url), url.resolvingSymlinksInPath().path != unreadableDirectory?.resolvingSymlinksInPath().path else { throw FileSystemError.unreadableContent(url) }
        return try await local.children(of: url)
    }
    func fileExists(_ url: URL) async -> Bool { contains(url) && FileManager.default.fileExists(atPath: url.path) }
    func isReadable(_ url: URL) async -> Bool { contains(url) && url.resolvingSymlinksInPath().path != unreadableDirectory?.resolvingSymlinksInPath().path }
    func isWritable(_ url: URL) -> Bool { false }
    func readData(at url: URL, maximumBytes: Int) async throws -> Data {
        guard contains(url) else { throw FileSystemError.unreadableContent(url) }
        return try await local.readData(at: url, maximumBytes: maximumBytes)
    }
    func readText(at url: URL, maximumBytes: Int) async throws -> String { String(decoding: try await readData(at: url, maximumBytes: maximumBytes), as: UTF8.self) }
    func move(_ source: URL, to destination: URL) throws { throw FileSystemError.trashUnavailable(source) }
    func createDirectory(_ url: URL) throws { throw FileSystemError.trashUnavailable(url) }
    func removeEmptyDirectory(_ url: URL) throws { throw FileSystemError.trashUnavailable(url) }
    func trash(_ url: URL) throws -> URL { throw FileSystemError.trashUnavailable(url) }
}

func runReviewCompletenessRegressionContracts() async throws {
    let manager = FileManager.default
    let home = manager.temporaryDirectory.appendingPathComponent("review-coverage-" + UUID().uuidString).resolvingSymlinksInPath()
    defer { try? manager.removeItem(at: home) }
    let providerRoot = home.appendingPathComponent(".codex")
    let boundary = providerRoot.appendingPathComponent("a/b/c/d/e/f/g/h")
    let omitted = boundary.appendingPathComponent("i/sentinel.txt")
    try manager.createDirectory(at: omitted.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("must remain untouched".utf8).write(to: omitted)
    let request = try ReadOnlyRequest(arguments: ["scan", "--module", "agentEnvironment", "--home", home.path])
    let fs = ReviewScanFileSystem(home: home)
    let partial = try await ReadOnlyInterface.run(request, runtime: CleanupRuntime(home: home, fileSystem: fs))
    require(partial.scan?.scanStatus == "partial" && partial.scan?.modules.first?.state == .limited,
            "depth-truncated Agent scan must not claim complete JSON results")
    require(partial.scan?.coverage.budgetLimitedModules.contains(.agentEnvironment) == true
            && partial.scan?.modules.first?.limitations.contains { $0.path?.resolvingSymlinksInPath().path == boundary.resolvingSymlinksInPath().path } == true,
            "JSON must identify the module and path limited by discovery depth")
    let object = try JSONSerialization.jsonObject(with: partial.json()) as! [String: Any]
    let scanObject = object["scan"] as! [String: Any]
    let providerCoverage = scanObject["agent_provider_coverage"] as? [[String: Any]]
    require(providerCoverage?.contains { $0["provider"] as? String == "codex" && $0["state"] as? String == "limited" } == true,
            "JSON must preserve provider-level completeness evidence")
    let context = ScanContext(homeDirectory: home, fileSystem: fs)
    guard let full = await SystemScanCoordinator().scan(context: context) else { throw ReadOnlyInterfaceError.scanUnavailable }
    require(full.modules[.agentEnvironment]?.state == .limited && full.coverage.budgetLimitedModules.contains(.agentEnvironment),
            "full GUI/system scan must retain Agent completeness and coverage")
    let inventory = try await AgentWorkspaceScanner(adapters: [CodexProviderAdapter()], maximumDepth: 8).scanAssetInventory(context: context)
    let refreshed = full.replacing(module: .agentEnvironment, payload: .agentEnvironment(inventory), completedAt: Date())
    require(refreshed.modules[.agentEnvironment]?.state == .limited && !refreshed.modules[.agentEnvironment]!.limitations.isEmpty
            && refreshed.coverage.budgetLimitedModules.contains(.agentEnvironment), "single-module refresh must not discard Agent limitations")
    let payload = try Data(contentsOf: omitted)
    require(payload == Data("must remain untouched".utf8), "completeness reporting must remain read-only")
    try manager.removeItem(at: omitted.deletingLastPathComponent())
    let complete = try await ReadOnlyInterface.run(request, runtime: CleanupRuntime(home: home, fileSystem: fs))
    require(complete.scan?.scanStatus == "complete", "an empty directory at the depth boundary is not omitted content")

    let denied = providerRoot.appendingPathComponent("blocked")
    try manager.createDirectory(at: denied, withIntermediateDirectories: true)
    let inaccessible = ReviewScanFileSystem(home: home, unreadableDirectory: denied)
    let unreadable = try await ReadOnlyInterface.run(request, runtime: CleanupRuntime(home: home, fileSystem: inaccessible))
    require(unreadable.scan?.scanStatus == "partial" && unreadable.scan?.coverage.unavailableRoots.contains { $0.resolvingSymlinksInPath().path == denied.resolvingSymlinksInPath().path } == true,
            "directory read failures must be visible in JSON completeness and unavailable paths")
    require(unreadable.scan?.modules.first?.limitations.contains { $0.path?.resolvingSymlinksInPath().path == denied.resolvingSymlinksInPath().path } == true,
            "directory read failure must explain its limitation")
    let unverifiable = ReviewScanFileSystem(home: home, unverifiablePath: providerRoot)
    let unavailable = try await ReadOnlyInterface.run(request, runtime: CleanupRuntime(home: home, fileSystem: unverifiable))
    require(unavailable.scan?.scanStatus == "partial" && unavailable.scan?.coverage.unavailableRoots.contains { $0.resolvingSymlinksInPath().path == providerRoot.resolvingSymlinksInPath().path } == true,
            "identity failure on a detected root must not be reported as not detected or complete")
    print("PASS: Agent JSON depth/read/identity completeness, provider evidence, empty boundary and read-only payload")
}

private enum ReviewRecoveryAction: CaseIterable { case restore, purge, reschedule, existingSchedule }

func runReviewRecoveryRegressionContracts() async throws {
    for action in ReviewRecoveryAction.allCases { try await runRecoveryInterleaving(action: action) }
    print("PASS: execution reconciliation serializes restore/purge/rescheduling and preserves existing retention")
}

private func runRecoveryInterleaving(action: ReviewRecoveryAction) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-recovery-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let home = URL(fileURLWithPath: "/Users/review-fixture")
    let quarantine = home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine")
    let now = Date(timeIntervalSince1970: 2_000)
    let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
    func candidate(_ name: String) -> CleanupCandidate {
        CleanupCandidate(url: home.appendingPathComponent("Library/Caches/" + name), displayName: name, category: .cache,
            bytes: 3, risk: .review, evidence: [], identity: identity, source: .general, lastAccessDate: nil, isActive: false)
    }
    let a = candidate("a"), b = candidate("b")
    let plan = try PlanBuilder(ruleVersion: "review").build(candidates: [a, b], selectedIDs: [a.id, b.id], now: now.addingTimeInterval(-500))
    let aDestination = quarantine.appendingPathComponent(plan.id.uuidString).appendingPathComponent(a.id.uuidString + "-a")
    let bDestination = quarantine.appendingPathComponent(plan.id.uuidString).appendingPathComponent(b.id.uuidString + "-b")
    let receipt = OperationReceipt(planID: plan.id, startedAt: plan.createdAt, completedAt: now.addingTimeInterval(-200), results: [
        OperationResult(candidateID: a.id, originalURL: a.url, destinationURL: aDestination, disposition: .quarantined, status: .succeeded, bytes: 3),
        OperationResult(candidateID: b.id, originalURL: b.url, destinationURL: bDestination, disposition: .failed, status: .failed, bytes: 3,
                        verificationNotBefore: now.addingTimeInterval(-1)),
    ], overallStatus: .partial)
    let fs = ReviewInterleavingFileSystem(entries: [aDestination: identity, b.url: identity], pause: b.url)
    let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home), quarantineRoot: quarantine,
        currentRuleVersion: "review", now: { now }, permanentRemove: { try await fs.remove($0) })
    let history = HistoryStore(url: root.appendingPathComponent("history.json"))
    let journal = ExecutionJournalStore(url: root.appendingPathComponent("execution.json"))
    let resolutions = ResolutionJournalStore(url: root.appendingPathComponent("resolutions.json"))
    let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedules.json"))
    let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules, executor: executor, resolutionJournalStore: resolutions)
    let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history, journalStore: journal,
        resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance, now: { now })
    try await history.upsert(receipt)
    try await journal.upsert(.init(id: receipt.id, plan: plan, startedAt: plan.createdAt, retentionPolicy: .manual))
    if action == .existingSchedule {
        try await coordinator.reschedule(receiptID: receipt.id, policy: .hours24, at: now)
    }
    let recovery = Task { try await coordinator.recoverPendingExecutions() }
    try await fs.waitUntilPaused()
    if action == .existingSchedule {
        await fs.release()
        _ = try await recovery.value
        let savedSchedule = try await coordinator.schedules().first { $0.receiptID == receipt.id }
        require(savedSchedule?.policy == .hours24 && savedSchedule?.scheduledAt == now,
                "execution reconciliation must preserve the user's already updated retention schedule")
        return
    }
    let completion = ReviewOperationCompletion()
    let operation = Task {
        switch action {
        case .restore: _ = try await coordinator.restore(receipt: receipt)
        case .purge: _ = try await coordinator.purge(receipt: receipt)
        case .reschedule: try await coordinator.reschedule(receiptID: receipt.id, policy: .hours24, at: now)
        case .existingSchedule: break
        }
        await completion.finish()
    }
    // A bounded overlap window allows the old, unlocked restore to finish. The
    // assertion observes transaction behavior, not the private gate machinery.
    let deadline = ContinuousClock.now.advanced(by: .milliseconds(500))
    while !(await completion.finished), ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(1)) }
    let completedDuringRecovery = await completion.finished
    await fs.release()
    _ = try await recovery.value
    try await operation.value
    let latest = try await coordinator.receipts().first { $0.id == receipt.id }
    let originalExists = await fs.fileExists(a.url)
    let quarantinedExists = await fs.fileExists(aDestination)
    require(!completedDuringRecovery, "manual \(action) must serialize with pending execution reconciliation")
    let savedSchedule = try await coordinator.schedules().first { $0.receiptID == receipt.id }
    switch action {
    case .restore:
        require(latest?.results.first?.disposition == .restored && originalExists && !quarantinedExists && savedSchedule == nil,
                "execution reconciliation must not resurrect restored quarantine history or its schedule")
    case .purge:
        require(latest?.results.first?.disposition == .permanentlyDeleted && !originalExists && !quarantinedExists && savedSchedule == nil,
                "execution reconciliation must not resurrect purged quarantine history or its schedule")
    case .reschedule:
        require(savedSchedule?.policy == .hours24 && savedSchedule?.scheduledAt == now, "serialized rescheduling must retain user's final policy")
    case .existingSchedule: break
    }
}
