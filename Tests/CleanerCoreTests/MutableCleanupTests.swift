import XCTest
@testable import CleanerCore

final class MutableCleanupTests: XCTestCase {
    func testAtomicCacheReplacementRefreshesPlanAndRemainsRecoverable() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".cache-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent("Library/Caches/com.apple.nsservicescache.plist")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        let fs = LocalFileSystem()
        let pack = try BundledCleanupRules.pack()
        let context = ScanContext(homeDirectory: home)
        let scanned = try await CleanupRuleEngine(pack: pack).scan(context: context)
        let candidate = try XCTUnwrap(scanned.first { $0.url == url })
        let plan = try PlanBuilder(ruleVersion: pack.executionVersion).build(candidates: [candidate], selectedIDs: [candidate.id])
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("old"))
        try Data("new cache".utf8).write(to: url)
        let runtime = CleanupRuntime(home: home)
        let refreshed = try await runtime.refreshMutableCleanupPlan(plan)
        XCTAssertNotEqual(refreshed.items[0].candidate.identity.inode, candidate.identity.inode)
        XCTAssertEqual(refreshed.id, plan.id)
        XCTAssertEqual(refreshed.expiresAt, plan.expiresAt)
        let journal = ExecutionJournalStore(url: home.appendingPathComponent("journal.json"))
        let executor = CleanupExecutor(fileSystem: fs, pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: pack.executionVersion,
            validateCandidate: { candidate in
                try await runtime.validateForExecution(candidate)
                if let entry = try await journal.entries().first {
                    XCTAssertEqual(entry.plan.items[0].candidate.identity, candidate.identity,
                        "the refreshed identity must be journaled before moving")
                }
            })
        let history = HistoryStore(url: home.appendingPathComponent("history.json"))
        let schedules = QuarantineScheduleStore(url: home.appendingPathComponent("schedules.json"))
        let resolutions = ResolutionJournalStore(url: home.appendingPathComponent("resolutions.json"))
        let maintenance = QuarantineMaintenanceCoordinator(historyStore: history, scheduleStore: schedules,
            executor: executor, resolutionJournalStore: resolutions)
        let coordinator = CleanupExecutionCoordinator(executor: executor, historyStore: history, journalStore: journal,
            resolutionJournalStore: resolutions, scheduleStore: schedules, maintenanceCoordinator: maintenance,
            now: Date.init, refreshPlan: { try await runtime.refreshMutableCleanupPlan($0) })
        let receipt = try await coordinator.execute(plan: plan, retentionPolicy: .hours24)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        let recovered = await executor.recoverInterruptedExecution(.init(id: receipt.id, plan: refreshed,
            startedAt: receipt.startedAt, retentionPolicy: .hours24))
        XCTAssertEqual(recovered.results.first?.status, .succeeded)
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
        XCTAssertEqual(try Data(contentsOf: url), Data("new cache".utf8))
        // A second replacement after refresh must not inherit the selected identity.
        try FileManager.default.moveItem(at: url, to: url.appendingPathExtension("new"))
        try Data("later replacement".utf8).write(to: url)
        let stale = await executor.execute(plan: refreshed)
        XCTAssertEqual(stale.results.first?.status, .skippedIdentityChanged)
        XCTAssertTrue(DefaultCleanupAttemptOutcome(attemptedCandidates: [candidate], receipt: stale).failures.first?.isRetryable == true)
        // A symlink never gains refresh authority.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: url.appendingPathExtension("new"))
        let linked = try await runtime.refreshMutableCleanupPlan(plan)
        XCTAssertEqual(linked, plan)
    }

    func testApplicationLogAppendUsesActualDiscoveryRule() async throws {
        let home = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(".log-fixture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: home) }
        let url = home.appendingPathComponent("Library/Containers/test.logger/Data/Library/Logs/app.log")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: url)
        let app = InstalledApplication(bundleURL: home.appendingPathComponent("Applications/Logger.app"),
            bundleIdentifier: "test.logger", name: "Logger", version: nil, isRunning: false, isSystem: false)
        let scanner = ApplicationCleanupScanner()
        let context = ScanContext(homeDirectory: home)
        let discovery = await scanner.discover(applications: [app], context: context)
        let scanned = try await scanner.scan(discovery: discovery, context: context)
        let candidate = try XCTUnwrap(scanned.candidates.first { $0.url == url })
        XCTAssertTrue(candidate.ruleID?.hasPrefix("system-cleanup.v1.") == true)
        let plan = try PlanBuilder().build(candidates: [candidate], selectedIDs: [candidate.id])
        let writer = try FileHandle(forWritingTo: url)
        try writer.seekToEnd(); try writer.write(contentsOf: Data(" appended".utf8)); try writer.close()
        let executor = CleanupExecutor(fileSystem: LocalFileSystem(), pathPolicy: .init(homeDirectory: home),
            quarantineRoot: home.appendingPathComponent("Quarantine"), currentRuleVersion: plan.ruleVersion,
            validateCandidate: { try await scanner.validateForExecution($0, context: context, applications: [app]) })
        let receipt = await executor.execute(plan: plan)
        XCTAssertEqual(receipt.results.first?.status, .succeeded)
        let restored = await executor.restore(receipt: receipt)
        XCTAssertEqual(restored.results.first?.status, .restored)
    }
}
