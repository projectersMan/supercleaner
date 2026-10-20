import CleanerCore
import Foundation

enum CleanerSmokeTest {
    enum Failure: Error { case cleanupFailed, historyMissing, restoreFailed }

    static func run() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("SuperCleaner-Smoke-\(UUID().uuidString)", isDirectory: true)
        defer { try? manager.removeItem(at: root) }
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("rebuildable.cache")
        try Data("fixture".utf8).write(to: original)

        let fileSystem = LocalFileSystem()
        let identity = try await fileSystem.identity(at: original)
        let candidate = CleanupCandidate(
            url: original, displayName: original.lastPathComponent, category: .cache,
            bytes: identity.size, risk: .safe,
            evidence: [Evidence(code: "smoke", summary: "isolated fixture")], identity: identity,
            source: .general, lastAccessDate: nil, isActive: false
        )
        let plan = try PlanBuilder(ruleVersion: "bundled-1").build(candidates: [candidate], selectedIDs: [candidate.id])
        let executor = CleanupExecutor(
            fileSystem: fileSystem,
            pathPolicy: PathPolicy(homeDirectory: root),
            quarantineRoot: root.appendingPathComponent("Quarantine", isDirectory: true),
            currentRuleVersion: "bundled-1"
        )
        let history = HistoryStore(url: root.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: root.appendingPathComponent("schedules.json"))
        let resolutionJournal = ResolutionJournalStore(
            url: root.appendingPathComponent("resolution-journal.json")
        )
        let maintenance = QuarantineMaintenanceCoordinator(
            historyStore: history,
            scheduleStore: schedules,
            executor: executor,
            resolutionJournalStore: resolutionJournal
        )
        let coordinator = CleanupExecutionCoordinator(
            executor: executor,
            historyStore: history,
            journalStore: ExecutionJournalStore(url: root.appendingPathComponent("journal.json")),
            resolutionJournalStore: resolutionJournal,
            scheduleStore: schedules,
            maintenanceCoordinator: maintenance,
            now: Date.init
        )
        let receipt = try await coordinator.execute(plan: plan, retentionPolicy: .hours24)
        guard receipt.overallStatus == .completed, !manager.fileExists(atPath: original.path) else { throw Failure.cleanupFailed }

        guard try await coordinator.receipts().contains(where: { $0.id == receipt.id }) else { throw Failure.historyMissing }

        let restore = try await coordinator.restore(receipt: receipt)
        guard restore.results.first?.status == .restored, manager.fileExists(atPath: original.path) else { throw Failure.restoreFailed }
    }
}
