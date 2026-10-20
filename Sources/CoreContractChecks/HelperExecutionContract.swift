import CleanerCore
import Foundation

private final class HelperFixtureClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_000)
    func now() -> Date { lock.withLock { value } }
    func set(_ seconds: TimeInterval) { lock.withLock { value = Date(timeIntervalSince1970: seconds) } }
}

private actor HelperFixtureFileSystem: FileSystemAccess {
    private var identities: [String: FileIdentity]
    private(set) var localMoves = 0
    private(set) var privilegedMoves = 0
    private(set) var privilegedPurges = 0
    init(source: URL, identity: FileIdentity) { identities = [source.path: identity] }
    func identity(at url: URL) throws -> FileIdentity { guard let value = identities[url.path] else { throw FileSystemError.missing(url) }; return value }
    func children(of url: URL) -> [URL] { [] }
    func isReadable(_ url: URL) -> Bool { true }
    func isWritable(_ url: URL) -> Bool { false }
    func fileExists(_ url: URL) -> Bool { identities[url.path] != nil }
    func createDirectory(_ url: URL) { }
    func removeEmptyDirectory(_ url: URL) { }
    func trash(_ url: URL) -> URL { url }
    func move(_ source: URL, to destination: URL) throws { localMoves += 1; try transfer(source, destination) }
    func helperMove(_ source: URL, _ destination: URL) throws { privilegedMoves += 1; try transfer(source, destination) }
    func helperPurge(_ source: URL) { privilegedPurges += 1; identities.removeValue(forKey: source.path) }
    private func transfer(_ source: URL, _ destination: URL) throws {
        guard identities[destination.path] == nil, let identity = identities.removeValue(forKey: source.path) else { throw HelperClientError.invalidResponse }
        identities[destination.path] = identity
    }
}

private struct FixturePrivilegedOperations: PrivilegedApplicationOperations {
    let fileSystem: HelperFixtureFileSystem
    var uncertainMove = false
    func moveToQuarantine(candidate: CleanupCandidate, destination: URL, planID: UUID) async throws -> Bool {
        if uncertainMove { throw HelperMutationUncertain() }
        try await fileSystem.helperMove(candidate.url, destination); return true
    }
    func restore(source: URL, destination: URL, planID: UUID) async throws -> Bool { try await fileSystem.helperMove(source, destination); return true }
    func purge(source: URL, planID: UUID) async throws -> Bool { await fileSystem.helperPurge(source); return true }
}

func runHelperExecutionContracts() async throws {
    let manager = FileManager.default
    let directory = manager.temporaryDirectory.appendingPathComponent("helper-execution-" + UUID().uuidString)
    defer { try? manager.removeItem(at: directory) }
    let source = URL(fileURLWithPath: "/Applications/ContractFixture.app")
    let home = URL(fileURLWithPath: "/Users/helper-fixture")
    let quarantine = home.appendingPathComponent("Library/Application Support/SuperCleaner/Quarantine")
    let identity = FileIdentity(device: 1, inode: 2, size: 3, modificationTime: 4, kind: .directory)
    let candidate = CleanupCandidate(url: source, displayName: "ContractFixture", category: .application, bytes: 3, risk: .review, evidence: [], identity: identity, source: .application, lastAccessDate: nil, isActive: false)
    let clock = HelperFixtureClock()
    func makePlan() -> CleanupPlan { .init(createdAt: clock.now(), expiresAt: clock.now().addingTimeInterval(300), items: [PlanItem(candidate: candidate, isSelected: true)], ruleVersion: "helper-fixture") }
    let fs = HelperFixtureFileSystem(source: source, identity: identity)
    let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home), quarantineRoot: quarantine, currentRuleVersion: "helper-fixture", now: clock.now,
        privilegedApplications: FixturePrivilegedOperations(fileSystem: fs), permanentRemove: { _ in require(false, "helper purge fell through to local removal") })
    let firstPlan = makePlan()
    let moved = await executor.execute(plan: firstPlan)
    let localMoves = await fs.localMoves
    let helperMoves = await fs.privilegedMoves
    require(moved.overallStatus == .completed && localMoves == 0 && helperMoves == 1, "executor must route authorized application body through helper exactly once")
    let restored = await executor.restore(receipt: moved)
    require(restored.results.first?.status == .restored, "helper-routed restore must pass identity post-verification")
    let movedAgain = await executor.execute(plan: makePlan())
    let purged = await executor.purge(receipt: movedAgain)
    let helperPurges = await fs.privilegedPurges
    require(purged.results.first?.status == .succeeded && helperPurges == 1, "helper-routed permanent purge must not invoke local recursive removal")

    let delayedFS = HelperFixtureFileSystem(source: source, identity: identity)
    let delayedExecutor = CleanupExecutor(fileSystem: delayedFS, pathPolicy: .init(homeDirectory: home), quarantineRoot: quarantine, currentRuleVersion: "helper-fixture", now: clock.now,
        privilegedApplications: FixturePrivilegedOperations(fileSystem: delayedFS, uncertainMove: true))
    let history = HistoryStore(url: directory.appendingPathComponent("history.json"))
    let journal = ExecutionJournalStore(url: directory.appendingPathComponent("execution.json"))
    let resolutions = ResolutionJournalStore(url: directory.appendingPathComponent("resolutions.json"))
    let schedules = QuarantineScheduleStore(url: directory.appendingPathComponent("schedules.json"))
    let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules, executor: delayedExecutor, resolutionJournalStore: resolutions)
    let coordinator = CleanupExecutionCoordinator(executor: delayedExecutor, historyStore: history, journalStore: journal, resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance, now: clock.now)
    let delayedPlan = makePlan()
    let pending = try await coordinator.execute(plan: delayedPlan, retentionPolicy: .manual)
    let pendingEntries = try await journal.entries()
    require(pending.results.first?.verificationNotBefore != nil && pendingEntries.count == 1, "uncertain XPC result must keep durable execution journal and quarantine destination")
    let beforeDeadline = try await coordinator.recoverPendingExecutions()
    let retained = try await journal.entries()
    require(beforeDeadline.first?.results.first?.verificationNotBefore != nil && retained.count == 1, "source still present is not proof that an in-flight request was cancelled")
    let lateDestination = quarantine.appendingPathComponent(delayedPlan.id.uuidString).appendingPathComponent(candidate.id.uuidString + "-" + source.lastPathComponent)
    try await delayedFS.helperMove(source, lateDestination)
    clock.set(1_151)
    let verified = try await coordinator.recoverPendingExecutions()
    let finishedEntries = try await journal.entries()
    require(verified.first?.results.first?.disposition == .quarantined && finishedEntries.isEmpty, "late helper completion must become recoverable history, not an orphaned file")
    let saved = try await history.receipt(id: pending.id)
    require(saved?.hasQuarantinedContent == true && saved?.results.first?.verificationNotBefore == nil, "reconciliation must update same receipt without re-executing file move")
    let delayedLocalMoves = await delayedFS.localMoves
    require(delayedLocalMoves == 0, "uncertain request must never retry via local filesystem")
    let crashPlan = makePlan()
    let untouchedFS = HelperFixtureFileSystem(source: source, identity: identity)
    let crashExecutor = CleanupExecutor(fileSystem: untouchedFS, pathPolicy: .init(homeDirectory: home), quarantineRoot: quarantine, currentRuleVersion: "helper-fixture", now: clock.now)
    let crashEntry = ExecutionJournalEntry(id: UUID(), plan: crashPlan, startedAt: clock.now(), retentionPolicy: .manual)
    let immediateRecovery = await crashExecutor.recoverInterruptedExecution(crashEntry)
    require(immediateRecovery.results.first?.verificationNotBefore != nil, "restart with no reply must respect last possible request deadline")
    clock.set(1_602)
    let expiredRecovery = await crashExecutor.recoverInterruptedExecution(crashEntry)
    require(expiredRecovery.results.first?.status == .skippedCancelled && expiredRecovery.results.first?.verificationNotBefore == nil, "unchanged source becomes unexecuted only after all possible tokens have expired")
    print("PASS: helper execution routing, restore verification, durable uncertain-result journal and late-completion recovery")
}
